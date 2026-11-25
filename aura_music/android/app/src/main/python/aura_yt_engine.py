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
# =============================================================================

import glob
import json
import os
import sys
import traceback

MAX_CAPTURED_LOG_LINES = 240


def _configure_tls_and_paths(update_dir: str | None, quickjs_path: str) -> None:
    if update_dir and os.path.isdir(update_dir) and update_dir not in sys.path:
        sys.path.insert(0, update_dir)

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
    try:
        import yt_dlp
        import yt_dlp_ejs

        lines.append(
            f"Versiones: Python {sys.version.split()[0]} | "
            f"yt-dlp {getattr(yt_dlp.version, '__version__', '?')} | "
            f"ejs {getattr(yt_dlp_ejs, 'version', '?')}"
        )
    except Exception:
        pass

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
    info = {
        "pythonVersion": sys.version.split()[0],
        "ytDlpVersion": "unknown",
        "ejsVersion": "unknown",
        "quickjsConfigured": bool(quickjs_path and os.path.exists(quickjs_path)),
    }
    try:
        import yt_dlp

        info["ytDlpVersion"] = getattr(yt_dlp.version, "__version__", "unknown")
    except Exception as exc:
        info["ytDlpError"] = str(exc)

    try:
        import yt_dlp_ejs

        info["ejsVersion"] = getattr(yt_dlp_ejs, "version", "unknown")
    except Exception as exc:
        info["ejsError"] = str(exc)

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
