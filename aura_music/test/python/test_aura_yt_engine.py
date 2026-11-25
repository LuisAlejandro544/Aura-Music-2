# =============================================================================
# test_aura_yt_engine.py — Tests unitarios del auto-actualizador yt-dlp / ejs
# -----------------------------------------------------------------------------
# Qué verifica este archivo:
#   - Comparación de versiones CalVer/SemVer/PEP-440 (`is_newer_version`).
#   - Protección anti-ZipSlip y validación SHA-256 en `install_wheel_to_update_dir`.
#   - Extracción atómica y recarga en caliente de `yt_dlp` y `yt_dlp_ejs` desde
#     un wheel local sin depender de red ni de pip.
#   - Limpieza controlada (`clear_updates`) restaurando el estado previo.
# =============================================================================

import hashlib
import json
import os
import sys
import tempfile
import unittest
import zipfile

ENGINE_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "../../android/app/src/main/python")
)
if ENGINE_DIR not in sys.path:
    sys.path.insert(0, ENGINE_DIR)

import aura_yt_engine  # noqa: E402


def _create_fake_wheel(
    dest_whl: str,
    files: dict[str, str],
) -> str:
    with zipfile.ZipFile(dest_whl, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for arcname, content in files.items():
            zf.writestr(arcname, content)
    h = hashlib.sha256()
    with open(dest_whl, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


class TestAuraYtEngineUpdater(unittest.TestCase):
    def setUp(self):
        self._orig_sys_path = list(sys.path)
        aura_yt_engine._purge_module_from_sys_modules("yt_dlp")
        aura_yt_engine._purge_module_from_sys_modules("yt_dlp_ejs")

    def tearDown(self):
        aura_yt_engine._purge_module_from_sys_modules("yt_dlp")
        aura_yt_engine._purge_module_from_sys_modules("yt_dlp_ejs")
        sys.path[:] = self._orig_sys_path

    def test_version_comparison_calver_and_semver(self):
        self.assertTrue(aura_yt_engine.is_newer_version("2026.04.01", "2026.03.17"))
        self.assertTrue(aura_yt_engine.is_newer_version("2026.04.01.post1", "2026.04.01"))
        self.assertFalse(aura_yt_engine.is_newer_version("2026.04.01", "2026.04.01"))
        self.assertFalse(aura_yt_engine.is_newer_version("2025.12.01", "2026.01.01"))
        self.assertTrue(aura_yt_engine.is_newer_version("0.5.0", "0.4.2"))
        self.assertTrue(aura_yt_engine.is_newer_version("0.5.0", "0.5.0rc1"))
        self.assertTrue(aura_yt_engine.is_newer_version("0.5.0", "unknown"))

    def test_install_wheel_extracts_and_hot_reloads(self):
        with tempfile.TemporaryDirectory() as tmp:
            update_dir = os.path.join(tmp, "updates")
            whl_yt = os.path.join(tmp, "yt_dlp-2099.1.1-py3-none-any.whl")
            sha_yt = _create_fake_wheel(
                whl_yt,
                {
                    "yt_dlp/__init__.py": "from . import version\n",
                    "yt_dlp/version.py": "__version__ = '2099.01.01'\n",
                    "yt_dlp-2099.1.1.dist-info/METADATA": "Name: yt-dlp\nVersion: 2099.01.01\n",
                },
            )

            installed_ver = aura_yt_engine.install_wheel_to_update_dir(
                package_name="yt-dlp",
                wheel_path=whl_yt,
                expected_sha256=sha_yt,
                update_dir=update_dir,
            )
            self.assertEqual(installed_ver, "2099.01.01")

            whl_ejs = os.path.join(tmp, "yt_dlp_ejs-9.9.9-py3-none-any.whl")
            sha_ejs = _create_fake_wheel(
                whl_ejs,
                {
                    "yt_dlp_ejs/__init__.py": "version = '9.9.9'\n",
                    "yt_dlp_ejs-9.9.9.dist-info/METADATA": "Name: yt-dlp-ejs\nVersion: 9.9.9\n",
                },
            )
            ejs_ver = aura_yt_engine.install_wheel_to_update_dir(
                package_name="yt-dlp-ejs",
                wheel_path=whl_ejs,
                expected_sha256=sha_ejs,
                update_dir=update_dir,
            )
            self.assertEqual(ejs_ver, "9.9.9")

            info = json.loads(aura_yt_engine.get_engine_info("", update_dir))
            self.assertEqual(info["ytDlpVersion"], "2099.01.01")
            self.assertEqual(info["ejsVersion"], "9.9.9")
            self.assertTrue(info["usingUpdatedYtDlp"])
            self.assertTrue(info["usingUpdatedEjs"])

            cleared = json.loads(aura_yt_engine.clear_updates(update_dir))
            self.assertTrue(cleared["ok"])
            self.assertTrue(cleared["removed"])
            self.assertFalse(os.path.exists(os.path.join(update_dir, "yt_dlp")))

    def test_rejects_bad_sha256_and_zipslip(self):
        with tempfile.TemporaryDirectory() as tmp:
            update_dir = os.path.join(tmp, "updates")
            whl = os.path.join(tmp, "bad.whl")
            _create_fake_wheel(
                whl,
                {"yt_dlp/version.py": "__version__ = '1.0'\n"},
            )
            with self.assertRaises(ValueError):
                aura_yt_engine.install_wheel_to_update_dir(
                    package_name="yt-dlp",
                    wheel_path=whl,
                    expected_sha256="0" * 64,
                    update_dir=update_dir,
                )

            slip_whl = os.path.join(tmp, "slip.whl")
            sha_slip = _create_fake_wheel(
                slip_whl,
                {"../evil.txt": "nope"},
            )
            with self.assertRaises(ValueError):
                aura_yt_engine.install_wheel_to_update_dir(
                    package_name="yt-dlp",
                    wheel_path=slip_whl,
                    expected_sha256=sha_slip,
                    update_dir=update_dir,
                )


if __name__ == "__main__":
    unittest.main()
