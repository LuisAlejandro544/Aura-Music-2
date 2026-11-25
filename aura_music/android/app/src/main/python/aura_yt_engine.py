# =============================================================================
# aura_yt_engine.py — Motor Python minimalista de descarga con yt-dlp + EJS
# -----------------------------------------------------------------------------
# Qué hace este archivo:
#   Ejecuta `yt-dlp` (instalado con --no-deps) y `yt-dlp-ejs` dentro del
#   intérprete Python embebido por Chaquopy utilizando únicamente la biblioteca
#   estándar de Python + `certifi` para TLS en Android 9+.
#   - Resuelve desafíos JavaScript de YouTube usando el binario nativo en Rust
#     `libaura_qjs.so` (QuickJS-ng) mediante `js_runtimes={'quickjs': ...}`.
#   - Descarga flujos de audio directo (M4A/AAC o WebM/Opus) sin requerir
#     FFmpeg GPL y captura el log técnico completo (debug/warnings/errors y
#     traceback) para diagnósticos en dispositivo móvil.
#   - Incluye auto-actualizador seguro vía PyPI JSON API + verificación SHA-256
#     para actualizar los wheels puros Python de `yt-dlp` y `yt-dlp-ejs` en
#     `filesDir/yt_dlp_updates/` con recarga en caliente de `sys.modules`.
# =============================================================================

import glob
import hashlib
import importlib
import importlib.metadata
import json
import os
import posixpath
import re
import shutil
import ssl
import sys
import time
import traceback
import urllib.error
import urllib.request
import zipfile

MAX_CAPTURED_LOG_LINES = 240
PYPI_BASE_URL = "https://pypi.org/pypi"
MANIFEST_FILENAME = "aura_yt_updates_manifest.json"
USER_AGENT = "AuraMusic-Android/1.0 (yt-dlp-updater)"

_MANAGED_PACKAGES = {
    "yt-dlp": {
        "module": "yt_dlp",
        "dist_prefixes": ("yt_dlp-", "yt-dlp-"),
    },
    "yt-dlp-ejs": {
        "module": "yt_dlp_ejs",
        "dist_prefixes": ("yt_dlp_ejs-", "yt-dlp-ejs-"),
    },
}


def _build_ssl_context():
    try:
        import certifi

        ca_bundle = certifi.where()
        if ca_bundle and os.path.isfile(ca_bundle):
            return ssl.create_default_context(cafile=ca_bundle)
    except Exception:
        pass
    return ssl.create_default_context()


def _configure_tls_and_paths(update_dir: str | None, quickjs_path: str = "") -> None:
    if update_dir:
        os.makedirs(update_dir, exist_ok=True)
        norm_dir = os.path.abspath(update_dir)
        # Mantener update_dir siempre al inicio de sys.path para priorizar wheels actualizados
        sys.path = [p for p in sys.path if os.path.abspath(p) != norm_dir]
        sys.path.insert(0, norm_dir)
        importlib.invalidate_caches()

    try:
        import certifi

        ca_bundle = certifi.where()
        if ca_bundle and os.path.isfile(ca_bundle):
            os.environ.setdefault("SSL_CERT_FILE", ca_bundle)
            os.environ.setdefault("REQUESTS_CA_BUNDLE", ca_bundle)
    except Exception:
        pass

    qjs_dir = os.path.dirname(quickjs_path) if quickjs_path else ""
    if qjs_dir:
        current_path = os.environ.get("PATH", "")
        if qjs_dir not in current_path.split(os.pathsep):
            os.environ["PATH"] = (
                f"{qjs_dir}{os.pathsep}{current_path}" if current_path else qjs_dir
            )


def _read_manifest(update_dir: str | None) -> dict:
    if not update_dir:
        return {}
    manifest_path = os.path.join(update_dir, MANIFEST_FILENAME)
    if not os.path.isfile(manifest_path):
        return {}
    try:
        with open(manifest_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _write_manifest(update_dir: str, manifest: dict) -> None:
    os.makedirs(update_dir, exist_ok=True)
    target = os.path.join(update_dir, MANIFEST_FILENAME)
    tmp = f"{target}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, target)


def _purge_module_from_sys_modules(module_name: str) -> None:
    to_remove = [
        name
        for name in list(sys.modules.keys())
        if name == module_name or name.startswith(f"{module_name}.")
    ]
    for name in to_remove:
        sys.modules.pop(name, None)
    importlib.invalidate_caches()


def _parse_version_key(raw: str) -> tuple:
    """Convierte una versión tipo CalVer/SemVer/PEP-440 en tupla comparable."""
    cleaned = (raw or "").strip()
    if not cleaned or cleaned.lower() == "unknown":
        return ((0,), 0, 0)

    # Separar sufijo .postN o pre-release (a/b/rc/dev)
    pre_rank = 3  # release final > rc/b/a > dev
    pre_num = 0
    post_num = 0

    m_post = re.search(r"\.post(\d+)", cleaned, flags=re.IGNORECASE)
    if m_post:
        post_num = int(m_post.group(1))
        cleaned = cleaned[: m_post.start()] + cleaned[m_post.end() :]

    m_dev = re.search(r"\.?dev(\d+)", cleaned, flags=re.IGNORECASE)
    if m_dev:
        pre_rank = 0
        pre_num = int(m_dev.group(1))
        cleaned = cleaned[: m_dev.start()] + cleaned[m_dev.end() :]
    else:
        m_pre = re.search(r"(rc|a|b)(\d+)", cleaned, flags=re.IGNORECASE)
        if m_pre:
            tag = m_pre.group(1).lower()
            pre_rank = {"a": 1, "b": 2, "rc": 2}.get(tag, 1)
            pre_num = int(m_pre.group(2))
            cleaned = cleaned[: m_pre.start()] + cleaned[m_pre.end() :]

    nums = tuple(int(part) for part in re.findall(r"\d+", cleaned))
    if not nums:
        nums = (0,)
    # Quitar ceros a la derecha de segmentos de release? No en CalVer (2025.03.31)
    return (nums, pre_rank, pre_num, post_num)


def is_newer_version(latest: str, current: str) -> bool:
    if not latest or latest.lower() == "unknown":
        return False
    if not current or current.lower() == "unknown":
        return True
    return _parse_version_key(latest) > _parse_version_key(current)


def _get_installed_yt_dlp_version() -> str:
    try:
        import yt_dlp

        ver = getattr(getattr(yt_dlp, "version", None), "__version__", None)
        if ver:
            return str(ver)
    except Exception:
        pass
    try:
        return importlib.metadata.version("yt-dlp")
    except Exception:
        return "unknown"


def _get_installed_ejs_version() -> str:
    try:
        return importlib.metadata.version("yt-dlp-ejs")
    except Exception:
        pass
    try:
        import yt_dlp_ejs

        for attr in ("__version__", "version"):
            val = getattr(yt_dlp_ejs, attr, None)
            if isinstance(val, str) and val.strip():
                return val.strip()
            if val is not None and hasattr(val, "__version__"):
                sub = getattr(val, "__version__", "")
                if sub:
                    return str(sub)
    except Exception:
        pass
    return "unknown"


def _fetch_pypi_package_metadata(package_name: str, timeout: int = 20) -> dict:
    url = f"{PYPI_BASE_URL}/{package_name}/json"
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        },
    )
    ctx = _build_ssl_context()
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        raw = resp.read().decode("utf-8")
    payload = json.loads(raw)
    info = payload.get("info") or {}
    latest_version = str(info.get("version") or "").strip()
    if not latest_version:
        raise ValueError(f"PyPI no devolvió versión para {package_name}")

    urls = payload.get("urls") or []
    if not urls:
        releases = payload.get("releases") or {}
        urls = releases.get(latest_version) or []

    wheel_entry = None
    for entry in urls:
        if entry.get("packagetype") != "bdist_wheel":
            continue
        fname = str(entry.get("filename") or "")
        if not fname.endswith(".whl"):
            continue
        if "none-any" in fname or entry.get("python_version") == "py3":
            wheel_entry = entry
            break
    if wheel_entry is None:
        for entry in urls:
            if entry.get("packagetype") == "bdist_wheel" and str(
                entry.get("filename") or ""
            ).endswith(".whl"):
                wheel_entry = entry
                break

    if wheel_entry is None or not wheel_entry.get("url"):
        raise ValueError(f"No se encontró wheel compatible para {package_name} {latest_version}")

    digests = wheel_entry.get("digests") or {}
    return {
        "package": package_name,
        "version": latest_version,
        "wheelUrl": str(wheel_entry["url"]),
        "filename": str(wheel_entry.get("filename") or f"{package_name}.whl"),
        "sha256": str(digests.get("sha256") or "").strip().lower(),
        "size": int(wheel_entry.get("size") or 0),
    }


def _safe_zip_member_relpath(member_name: str) -> str | None:
    if not member_name or member_name.endswith("/"):
        return None
    norm = posixpath.normpath(member_name)
    if norm.startswith("/") or norm == ".." or norm.startswith("../"):
        raise ValueError(f"Entrada insegura en wheel: {member_name}")
    parts = [p for p in norm.split("/") if p]
    if not parts or any(p == ".." for p in parts):
        raise ValueError(f"Ruta inválida en wheel: {member_name}")
    return os.path.join(*parts)


def install_wheel_to_update_dir(
    package_name: str,
    wheel_path: str,
    expected_sha256: str,
    update_dir: str,
) -> str:
    if package_name not in _MANAGED_PACKAGES:
        raise ValueError(f"Paquete no gestionado: {package_name}")

    pkg_cfg = _MANAGED_PACKAGES[package_name]
    pkg_module = pkg_cfg["module"]
    dist_prefixes = pkg_cfg["dist_prefixes"]

    if expected_sha256:
        hasher = hashlib.sha256()
        with open(wheel_path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                hasher.update(chunk)
        actual = hasher.hexdigest().lower()
        if actual != expected_sha256.lower():
            raise ValueError(
                f"SHA-256 inválido para {package_name}: esperado {expected_sha256}, recibido {actual}"
            )

    os.makedirs(update_dir, exist_ok=True)
    staging_dir = os.path.join(update_dir, f".staging_{pkg_module}")
    if os.path.exists(staging_dir):
        shutil.rmtree(staging_dir, ignore_errors=True)
    os.makedirs(staging_dir, exist_ok=True)

    try:
        with zipfile.ZipFile(wheel_path, "r") as zf:
            for info in zf.infolist():
                rel = _safe_zip_member_relpath(info.filename)
                if rel is None:
                    continue
                top_dir = info.filename.split("/", 1)[0]
                if top_dir != pkg_module and not (
                    top_dir.endswith(".dist-info")
                    and top_dir.lower().startswith(dist_prefixes)
                ):
                    continue
                dest_path = os.path.join(staging_dir, rel)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                with zf.open(info, "r") as src, open(dest_path, "wb") as dst:
                    shutil.copyfileobj(src, dst)

        staged_pkg_dir = os.path.join(staging_dir, pkg_module)
        if not os.path.isdir(staged_pkg_dir):
            raise ValueError(f"El wheel de {package_name} no contiene el módulo '{pkg_module}'")

        # Eliminar versiones previas en update_dir antes de mover las nuevas
        target_pkg_dir = os.path.join(update_dir, pkg_module)
        if os.path.exists(target_pkg_dir):
            shutil.rmtree(target_pkg_dir)

        for entry in os.listdir(update_dir):
            if entry.endswith(".dist-info") and entry.lower().startswith(dist_prefixes):
                shutil.rmtree(os.path.join(update_dir, entry), ignore_errors=True)

        shutil.move(staged_pkg_dir, target_pkg_dir)
        for entry in os.listdir(staging_dir):
            if entry.endswith(".dist-info") and entry.lower().startswith(dist_prefixes):
                shutil.move(
                    os.path.join(staging_dir, entry),
                    os.path.join(update_dir, entry),
                )
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)

    _configure_tls_and_paths(update_dir)
    _purge_module_from_sys_modules(pkg_module)
    importlib.import_module(pkg_module)
    if package_name == "yt-dlp":
        return _get_installed_yt_dlp_version()
    return _get_installed_ejs_version()


def _download_wheel_file(
    wheel_url: str,
    dest_path: str,
    total_hint: int,
    package_name: str,
    progress_callback=None,
) -> None:
    req = urllib.request.Request(wheel_url, headers={"User-Agent": USER_AGENT})
    ctx = _build_ssl_context()
    with urllib.request.urlopen(req, timeout=30, context=ctx) as resp, open(
        dest_path, "wb"
    ) as out_fh:
        total = int(resp.headers.get("Content-Length") or total_hint or 0)
        downloaded = 0
        while True:
            chunk = resp.read(65536)
            if not chunk:
                break
            out_fh.write(chunk)
            downloaded += len(chunk)
            if progress_callback is not None:
                pct = (downloaded / total * 100.0) if total > 0 else 0.0
                _emit_update_progress(
                    progress_callback,
                    stage="downloading_update",
                    package_name=package_name,
                    percent=pct,
                    downloaded=downloaded,
                    total=total,
                    message=f"Descargando {package_name}...",
                )


def _emit_update_progress(
    progress_callback,
    stage: str,
    package_name: str,
    percent: float,
    downloaded: int,
    total: int,
    message: str,
) -> None:
    if progress_callback is None:
        return
    try:
        if hasattr(progress_callback, "onProgress"):
            progress_callback.onProgress(
                str(stage),
                str(package_name),
                float(percent),
                int(downloaded),
                int(total),
                str(message),
            )
        else:
            progress_callback(
                stage,
                package_name,
                float(percent),
                int(downloaded),
                int(total),
                str(message),
            )
    except Exception:
        pass


def check_updates(update_dir: str = "", quickjs_path: str = "") -> str:
    _configure_tls_and_paths(update_dir or None, quickjs_path)
    installed_yt = _get_installed_yt_dlp_version()
    installed_ejs = _get_installed_ejs_version()
    manifest = _read_manifest(update_dir)
    now_ms = int(time.time() * 1000)

    try:
        meta_yt = _fetch_pypi_package_metadata("yt-dlp")
        meta_ejs = _fetch_pypi_package_metadata("yt-dlp-ejs")
        yt_avail = is_newer_version(meta_yt["version"], installed_yt)
        ejs_avail = is_newer_version(meta_ejs["version"], installed_ejs)

        if update_dir:
            manifest["lastCheckMs"] = now_ms
            _write_manifest(update_dir, manifest)

        return json.dumps(
            {
                "ok": True,
                "checkedAtMs": now_ms,
                "hasUpdates": yt_avail or ejs_avail,
                "ytDlp": {
                    "installed": installed_yt,
                    "latest": meta_yt["version"],
                    "updateAvailable": yt_avail,
                },
                "ytDlpEjs": {
                    "installed": installed_ejs,
                    "latest": meta_ejs["version"],
                    "updateAvailable": ejs_avail,
                },
            }
        )
    except Exception as exc:
        return json.dumps(
            {
                "ok": False,
                "checkedAtMs": now_ms,
                "hasUpdates": False,
                "ytDlp": {
                    "installed": installed_yt,
                    "latest": "",
                    "updateAvailable": False,
                },
                "ytDlpEjs": {
                    "installed": installed_ejs,
                    "latest": "",
                    "updateAvailable": False,
                },
                "error": f"No se pudo consultar PyPI: {exc}",
                "rawError": traceback.format_exc(),
            }
        )


def check_and_update_packages(
    update_dir: str,
    cache_dir: str,
    quickjs_path: str = "",
    force: bool = False,
    progress_callback=None,
) -> str:
    _configure_tls_and_paths(update_dir or None, quickjs_path)
    os.makedirs(update_dir, exist_ok=True)
    os.makedirs(cache_dir, exist_ok=True)

    installed_yt = _get_installed_yt_dlp_version()
    installed_ejs = _get_installed_ejs_version()
    manifest = _read_manifest(update_dir)
    now_ms = int(time.time() * 1000)

    _emit_update_progress(
        progress_callback,
        stage="checking",
        package_name="yt-dlp",
        percent=5.0,
        downloaded=0,
        total=0,
        message="Consultando últimas versiones en PyPI...",
    )

    try:
        targets = [
            ("yt-dlp", installed_yt),
            ("yt-dlp-ejs", installed_ejs),
        ]
        results = {}
        updated_any = False

        for pkg_name, current_ver in targets:
            meta = _fetch_pypi_package_metadata(pkg_name)
            latest_ver = meta["version"]
            needs_update = force or is_newer_version(latest_ver, current_ver)
            updated = False
            final_ver = current_ver

            if needs_update and latest_ver != current_ver:
                tmp_whl = os.path.join(cache_dir, f"{pkg_name}_{latest_ver}.whl.tmp")
                try:
                    _emit_update_progress(
                        progress_callback,
                        stage="downloading_update",
                        package_name=pkg_name,
                        percent=15.0,
                        downloaded=0,
                        total=meta["size"],
                        message=f"Descargando {pkg_name} {latest_ver}...",
                    )
                    _download_wheel_file(
                        wheel_url=meta["wheelUrl"],
                        dest_path=tmp_whl,
                        total_hint=meta["size"],
                        package_name=pkg_name,
                        progress_callback=progress_callback,
                    )
                    _emit_update_progress(
                        progress_callback,
                        stage="installing",
                        package_name=pkg_name,
                        percent=92.0,
                        downloaded=meta["size"],
                        total=meta["size"],
                        message=f"Instalando {pkg_name} {latest_ver}...",
                    )
                    final_ver = install_wheel_to_update_dir(
                        package_name=pkg_name,
                        wheel_path=tmp_whl,
                        expected_sha256=meta["sha256"],
                        update_dir=update_dir,
                    )
                    updated = True
                    updated_any = True
                    manifest_key = "ytDlp" if pkg_name == "yt-dlp" else "ytDlpEjs"
                    manifest[manifest_key] = {
                        "version": final_ver,
                        "updatedAtMs": int(time.time() * 1000),
                    }
                finally:
                    if os.path.exists(tmp_whl):
                        try:
                            os.remove(tmp_whl)
                        except OSError:
                            pass

            results[pkg_name] = {
                "installed": final_ver,
                "previous": current_ver,
                "latest": latest_ver,
                "updated": updated,
                "updateAvailable": is_newer_version(latest_ver, final_ver),
            }

        manifest["lastCheckMs"] = now_ms
        if updated_any:
            manifest["lastUpdateMs"] = int(time.time() * 1000)
        _write_manifest(update_dir, manifest)

        _emit_update_progress(
            progress_callback,
            stage="done",
            package_name="",
            percent=100.0,
            downloaded=0,
            total=0,
            message="Motor actualizado" if updated_any else "Ya tienes las últimas versiones",
        )

        msg = (
            f"Actualizado a yt-dlp {results['yt-dlp']['installed']} · ejs {results['yt-dlp-ejs']['installed']}"
            if updated_any
            else "yt-dlp y yt-dlp-ejs ya están al día"
        )
        return json.dumps(
            {
                "ok": True,
                "updatedAny": updated_any,
                "checkedAtMs": now_ms,
                "message": msg,
                "ytDlp": results["yt-dlp"],
                "ytDlpEjs": results["yt-dlp-ejs"],
            }
        )
    except Exception as exc:
        return json.dumps(
            {
                "ok": False,
                "updatedAny": False,
                "checkedAtMs": now_ms,
                "message": f"Error actualizando motor: {exc}",
                "error": f"No se pudo actualizar el motor: {exc}",
                "rawError": traceback.format_exc(),
                "ytDlp": {"installed": _get_installed_yt_dlp_version()},
                "ytDlpEjs": {"installed": _get_installed_ejs_version()},
            }
        )


def clear_updates(update_dir: str) -> str:
    removed = False
    if update_dir and os.path.isdir(update_dir):
        for pkg_cfg in _MANAGED_PACKAGES.values():
            pkg_dir = os.path.join(update_dir, pkg_cfg["module"])
            if os.path.exists(pkg_dir):
                shutil.rmtree(pkg_dir, ignore_errors=True)
                removed = True
            for entry in os.listdir(update_dir):
                if entry.endswith(".dist-info") and entry.lower().startswith(
                    pkg_cfg["dist_prefixes"]
                ):
                    shutil.rmtree(os.path.join(update_dir, entry), ignore_errors=True)
                    removed = True
        manifest_path = os.path.join(update_dir, MANIFEST_FILENAME)
        if os.path.exists(manifest_path):
            try:
                os.remove(manifest_path)
            except OSError:
                pass
    _purge_module_from_sys_modules("yt_dlp")
    _purge_module_from_sys_modules("yt_dlp_ejs")
    return json.dumps(
        {
            "ok": True,
            "removed": removed,
            "ytDlpVersion": _get_installed_yt_dlp_version(),
            "ejsVersion": _get_installed_ejs_version(),
        }
    )


def _format_selector(format_pref: str) -> str:
    pref = (format_pref or "best").strip().lower()
    if pref == "m4a":
        return "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio/best"
    if pref == "opus":
        return "bestaudio[ext=webm]/bestaudio[acodec=opus]/bestaudio/best"
    return "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best"


def _find_downloaded_thumbnail(output_dir: str, file_id: str) -> str:
    if not file_id:
        return ""
    for ext in ("webp", "jpg", "jpeg", "png"):
        candidate = os.path.join(output_dir, f"{file_id}.{ext}")
        if os.path.isfile(candidate) and os.path.getsize(candidate) > 0:
            return candidate
    matches = sorted(glob.glob(os.path.join(output_dir, f"{file_id}.*")))
    for path in matches:
        lower = path.lower()
        if lower.endswith((".webp", ".jpg", ".jpeg", ".png")) and os.path.getsize(path) > 0:
            return path
    return ""


class _CaptureLogger:
    def __init__(self, on_stage=None):
        self._on_stage = on_stage
        self.logs: list[str] = []
        self.warnings: list[str] = []
        self.errors: list[str] = []

    def _append(self, level: str, msg: str) -> None:
        line = f"[{level}] {msg}"
        self.logs.append(line)
        if len(self.logs) > MAX_CAPTURED_LOG_LINES:
            self.logs.pop(0)

    def debug(self, msg: str) -> None:
        text = str(msg)
        self._append("DEBUG", text)
        if self._on_stage and "Solving JS challenges" in text:
            self._on_stage("ejs", "Resolviendo desafío JS con Rust QuickJS-ng...")

    def info(self, msg: str) -> None:
        text = str(msg)
        self._append("INFO", text)
        if self._on_stage and "Solving JS challenges" in text:
            self._on_stage("ejs", "Resolviendo desafío JS con Rust QuickJS-ng...")

    def warning(self, msg: str) -> None:
        text = str(msg)
        self.warnings.append(text)
        self._append("WARN", text)

    def error(self, msg: str) -> None:
        text = str(msg)
        self.errors.append(text)
        self._append("ERROR", text)


def _summarize_error(raw_errors: list[str], logger: _CaptureLogger) -> str:
    combined = "\n".join(raw_errors + logger.errors + logger.warnings).lower()

    if "sign in to confirm" in combined or "not a bot" in combined:
        return "YouTube pidió verificación anti-bot para esta conexión o video."
    if "http error 403" in combined or "403: forbidden" in combined:
        return "YouTube rechazó la descarga del flujo de audio (HTTP 403)."
    if "video unavailable" in combined or "private video" in combined:
        return "El video no está disponible o es privado."
    if "age-restricted" in combined or "confirm your age" in combined:
        return "El enlace requiere inicio de sesión por restricción de edad."
    if "requested format is not available" in combined:
        return "El formato de audio solicitado no está disponible para este enlace."
    if "nameresolutionerror" in combined or "failed to resolve" in combined or "timed out" in combined:
        return "No hubo respuesta de red o falló la resolución DNS al conectar."
    if "ssl" in combined or "certificate" in combined:
        return "Error de certificado TLS/SSL al conectar con el servidor."
    if (
        ("quickjs" in combined or "libaura_qjs" in combined or "yt-dlp-ejs" in combined)
        and any(tok in combined for tok in ("error", "failed", "enoent", "permission", "unable", "challenge", "not found"))
    ):
        return "Falló la resolución JavaScript (QuickJS-ng / yt-dlp-ejs)."

    if raw_errors:
        last_line = raw_errors[-1].strip().splitlines()[-1].strip()
        if last_line:
            return last_line[:220]
    return "No se pudo descargar el audio desde este enlace."


def _build_raw_report(
    url: str,
    format_pref: str,
    quickjs_path: str,
    attempt_reports: list[str],
    logger: _CaptureLogger,
) -> str:
    qjs_exists = bool(quickjs_path and os.path.exists(quickjs_path))
    lines = [
        f"URL: {url}",
        f"Formato preferido: {format_pref}",
        f"QuickJS-ng path: {quickjs_path or '(vacío)'} (existe={qjs_exists})",
    ]
    lines.append(
        f"Versiones: Python {sys.version.split()[0]} | "
        f"yt-dlp {_get_installed_yt_dlp_version()} | "
        f"ejs {_get_installed_ejs_version()}"
    )

    if attempt_reports:
        lines.append("")
        lines.append("=== Errores por intento ===")
        lines.extend(attempt_reports)

    if logger.logs:
        lines.append("")
        lines.append("=== Log interno yt-dlp ===")
        lines.extend(logger.logs)

    return "\n".join(lines)


def get_engine_info(quickjs_path: str = "", update_dir: str = "") -> str:
    _configure_tls_and_paths(update_dir or None, quickjs_path)
    using_updated_yt = bool(
        update_dir and os.path.isdir(os.path.join(update_dir, "yt_dlp"))
    )
    using_updated_ejs = bool(
        update_dir and os.path.isdir(os.path.join(update_dir, "yt_dlp_ejs"))
    )
    info = {
        "pythonVersion": sys.version.split()[0],
        "ytDlpVersion": _get_installed_yt_dlp_version(),
        "ejsVersion": _get_installed_ejs_version(),
        "quickjsConfigured": bool(quickjs_path and os.path.exists(quickjs_path)),
        "usingUpdatedYtDlp": using_updated_yt,
        "usingUpdatedEjs": using_updated_ejs,
    }
    return json.dumps(info)


def download_audio(
    url: str,
    output_dir: str,
    cache_dir: str,
    quickjs_path: str,
    format_pref: str = "best",
    update_dir: str = "",
    progress_callback=None,
) -> str:
    _configure_tls_and_paths(update_dir or None, quickjs_path)
    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(cache_dir, exist_ok=True)

    try:
        import yt_dlp
    except Exception as exc:
        return json.dumps(
            {
                "ok": False,
                "error": f"No se pudo cargar yt-dlp: {exc}",
                "rawError": traceback.format_exc(),
            }
        )

    def emit_progress(stage: str, percent: float, downloaded: int, total: int, message: str):
        if progress_callback is None:
            return
        try:
            if hasattr(progress_callback, "onProgress"):
                progress_callback.onProgress(
                    str(stage),
                    float(percent),
                    int(downloaded),
                    int(total),
                    str(message),
                )
            else:
                progress_callback(stage, float(percent), int(downloaded), int(total), str(message))
        except Exception:
            pass

    def emit_stage(stage: str, message: str):
        emit_progress(stage, 0.0, 0, 0, message)

    logger = _CaptureLogger(on_stage=emit_stage)

    def progress_hook(data: dict):
        status = data.get("status")
        if status == "downloading":
            downloaded = int(data.get("downloaded_bytes") or 0)
            total = int(data.get("total_bytes") or data.get("total_bytes_estimate") or 0)
            pct = (downloaded / total * 100.0) if total > 0 else 0.0
            emit_progress("downloading", pct, downloaded, total, "Descargando audio con yt-dlp...")
        elif status == "finished":
            total = int(data.get("total_bytes") or data.get("downloaded_bytes") or 0)
            emit_progress("verifying", 100.0, total, total, "Descarga completa, verificando con Rust...")

    js_runtimes = {"quickjs": {"path": quickjs_path}} if quickjs_path else {"quickjs": {}}

    base_opts = {
        "format": _format_selector(format_pref),
        "outtmpl": os.path.join(output_dir, "%(id)s.%(ext)s"),
        "cachedir": cache_dir,
        "writethumbnail": True,
        "noplaylist": True,
        "noprogress": True,
        "no_color": True,
        "quiet": True,
        "verbose": True,
        "retries": 3,
        "fragment_retries": 5,
        "socket_timeout": 25,
        "js_runtimes": js_runtimes,
        "logger": logger,
        "progress_hooks": [progress_hook],
    }

    attempts = [
        ("Intento 1 (cliente por defecto)", base_opts),
        (
            "Intento 2 (player_client=android_vr,tv,web)",
            {
                **base_opts,
                "extractor_args": {"youtube": {"player_client": ["android_vr", "tv", "web"]}},
            },
        ),
    ]

    attempt_summaries: list[str] = []
    attempt_reports: list[str] = []
    emit_stage("resolving", "Analizando enlace y formatos con yt-dlp...")

    for idx, (label, opts) in enumerate(attempts):
        logger._append("INFO", f"--- {label} ---")
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=True)
                if not info:
                    msg = "yt-dlp no devolvió información del enlace"
                    attempt_summaries.append(msg)
                    attempt_reports.append(f"[{label}] {msg}")
                    continue

                if "entries" in info and info["entries"]:
                    info = next((e for e in info["entries"] if e), info)

                file_id = str(info.get("id") or "track")
                audio_path = ydl.prepare_filename(info)
                if not os.path.isfile(audio_path):
                    requested = info.get("requested_downloads") or []
                    for item in requested:
                        cand = item.get("filepath")
                        if cand and os.path.isfile(cand):
                            audio_path = cand
                            break

                if not os.path.isfile(audio_path) or os.path.getsize(audio_path) == 0:
                    msg = f"El archivo descargado está vacío o no existe ({audio_path})"
                    attempt_summaries.append(msg)
                    attempt_reports.append(f"[{label}] {msg}")
                    continue

                thumb_path = _find_downloaded_thumbnail(output_dir, file_id)
                title = (info.get("track") or info.get("title") or file_id).strip()
                artist = (
                    info.get("artist")
                    or info.get("uploader")
                    or info.get("channel")
                    or "Artista desconocido"
                ).strip()
                album = (info.get("album") or "Descargas Aura").strip()
                duration_sec = info.get("duration") or 0
                duration_ms = int(float(duration_sec) * 1000) if duration_sec else 0

                return json.dumps(
                    {
                        "ok": True,
                        "audioPath": audio_path,
                        "thumbnailPath": thumb_path,
                        "title": title,
                        "artist": artist,
                        "album": album,
                        "durationMs": duration_ms,
                        "ext": str(info.get("ext") or ""),
                        "videoId": file_id,
                        "webpageUrl": str(info.get("webpage_url") or url),
                        "abr": int(info.get("abr") or 0),
                        "asr": int(info.get("asr") or 0),
                    }
                )
        except Exception as exc:
            err_str = str(exc)
            attempt_summaries.append(err_str)
            attempt_reports.append(f"[{label}] {err_str}\n{traceback.format_exc().strip()}")
            if idx == 0:
                emit_stage("resolving", "Reintentando extracción con perfil alternativo...")

    summary = _summarize_error(attempt_summaries, logger)
    raw_report = _build_raw_report(
        url=url,
        format_pref=format_pref,
        quickjs_path=quickjs_path,
        attempt_reports=attempt_reports,
        logger=logger,
    )
    return json.dumps({"ok": False, "error": summary, "rawError": raw_report})
