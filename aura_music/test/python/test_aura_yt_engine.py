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


class TestAuraYtEngineExploreAndStream(unittest.TestCase):
    def setUp(self):
        self._orig_sys_path = list(sys.path)
        aura_yt_engine._purge_module_from_sys_modules("yt_dlp")

    def tearDown(self):
        aura_yt_engine._purge_module_from_sys_modules("yt_dlp")
        sys.path[:] = self._orig_sys_path

    def test_normalize_explore_target_and_parse_entries(self):
        target, is_url = aura_yt_engine._normalize_explore_target("lofi beats", limit=12)
        self.assertEqual(target, "ytsearch12:lofi beats")
        self.assertFalse(is_url)

        url_target, is_url_flag = aura_yt_engine._normalize_explore_target(
            "https://www.youtube.com/playlist?list=PL123", limit=20
        )
        self.assertEqual(url_target, "https://www.youtube.com/playlist?list=PL123")
        self.assertTrue(is_url_flag)

        parsed = aura_yt_engine._parse_explore_entry(
            {
                "id": "dQw4w9WgXcQ",
                "title": "Test Track",
                "uploader": "Aura Artist",
                "duration": 185.5,
                "view_count": 4200,
            }
        )
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed["videoId"], "dQw4w9WgXcQ")
        self.assertEqual(parsed["durationMs"], 185500)
        self.assertEqual(
            parsed["webpageUrl"], "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        self.assertIn("hqdefault.jpg", parsed["thumbnailUrl"])

        self.assertIsNone(
            aura_yt_engine._parse_explore_entry(
                {"id": "priv1234567", "title": "[Private video]"}
            )
        )
        self.assertIsNone(
            aura_yt_engine._parse_explore_entry(
                {"id": "live1234567", "title": "Radio 24/7", "is_live": True, "live_status": "is_live"}
            )
        )

    def test_search_explore_and_resolve_stream_with_mocked_yt_dlp(self):
        import types

        fake_yt_dlp = types.ModuleType("yt_dlp")

        class FakeYoutubeDL:
            def __init__(self, opts):
                self.opts = opts

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def extract_info(self, target, download=True):
                self.opts["logger"].debug("Solving JS challenges with quickjs")
                if target.startswith("ytsearch"):
                    return {
                        "entries": [
                            {
                                "id": "abc12345678",
                                "title": "Acoustic Horizon",
                                "artist": "Aura Trio",
                                "duration": 210,
                                "thumbnail": "https://i.ytimg.com/vi/abc12345678/hqdefault.jpg",
                            },
                            {
                                "id": "abc12345678",
                                "title": "Duplicate entry",
                            },
                            {
                                "id": "dead0000001",
                                "title": "[Deleted video]",
                            },
                        ]
                    }
                return {
                    "id": "abc12345678",
                    "title": "Acoustic Horizon",
                    "artist": "Aura Trio",
                    "duration": 210,
                    "ext": "m4a",
                    "abr": 128,
                    "asr": 44100,
                    "url": "https://cdn.example.test/audio.m4a?expire=9999999999",
                    "http_headers": {"User-Agent": "MockAgent/1.0"},
                    "webpage_url": target,
                }

        fake_yt_dlp.YoutubeDL = FakeYoutubeDL
        sys.modules["yt_dlp"] = fake_yt_dlp

        search_res = json.loads(aura_yt_engine.search_explore("acoustic horizon", limit=10))
        self.assertTrue(search_res["ok"])
        self.assertEqual(len(search_res["items"]), 1)
        self.assertEqual(search_res["items"][0]["videoId"], "abc12345678")

        stream_res = json.loads(
            aura_yt_engine.resolve_stream("https://www.youtube.com/watch?v=abc12345678")
        )
        self.assertTrue(stream_res["ok"])
        self.assertEqual(stream_res["mimeType"], "audio/mp4")
        self.assertEqual(stream_res["httpHeaders"]["User-Agent"], "MockAgent/1.0")
        self.assertEqual(stream_res["expiresAtMs"], 9999999999 * 1000)

    def test_recommendation_helpers_and_rd_mix_feed(self):
        import types

        self.assertTrue(aura_yt_engine.is_generic_artist_name("Artista desconocido"))
        self.assertFalse(aura_yt_engine.is_generic_artist_name("Soda Stereo"))
        self.assertEqual(
            aura_yt_engine.normalize_music_title("Luna (Official Music Video) [HD]"),
            "luna",
        )
        self.assertTrue(aura_yt_engine.is_reasonable_music_duration(210_000))
        self.assertFalse(aura_yt_engine.is_reasonable_music_duration(18_000))
        self.assertFalse(aura_yt_engine.is_reasonable_music_duration(3_600_000))
        self.assertEqual(
            aura_yt_engine.build_rd_mix_url("dQw4w9WgXcQ"),
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ",
        )
        self.assertEqual(aura_yt_engine.build_rd_mix_url("bad_id"), "")

        fake_yt_dlp = types.ModuleType("yt_dlp")

        class FakeMixYdl:
            def __init__(self, opts):
                self.opts = opts

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def extract_info(self, target, download=False):
                if target.startswith("ytsearch1:"):
                    return {
                        "entries": [
                            {
                                "id": "seed1234567",
                                "title": "Local Song",
                                "artist": "Local Band",
                                "duration": 205,
                            }
                        ]
                    }
                if "list=RDseed1234567" in target:
                    return {
                        "entries": [
                            {
                                "id": "seed1234567",
                                "title": "Local Song",
                                "artist": "Local Band",
                                "duration": 205,
                            },
                            {
                                "id": "skip9999999",
                                "title": "Skipped Song",
                                "artist": "Skip Artist",
                                "duration": 180,
                            },
                            {
                                "id": "mixtrack001",
                                "title": "Echoes (Official Audio)",
                                "artist": "Similar One",
                                "duration": 220,
                            },
                            {
                                "id": "podcast0001",
                                "title": "2 Hour Podcast",
                                "artist": "Talk Show",
                                "duration": 7200,
                            },
                        ]
                    }
                if "list=RDstream76543" in target:
                    return {
                        "entries": [
                            {
                                "id": "mixtrack002",
                                "title": "Warm Guitar",
                                "artist": "Similar Two",
                                "duration": 195,
                            },
                            {
                                "id": "mixtrack001",
                                "title": "Echoes",
                                "artist": "Similar One",
                                "duration": 220,
                            },
                        ]
                    }
                if "artists like" in target or "similar" in target:
                    return {
                        "entries": [
                            {
                                "id": "disc0000001",
                                "title": "Fresh Discovery",
                                "artist": "New Indie",
                                "duration": 240,
                            }
                        ]
                    }
                return {
                    "entries": [
                        {
                            "id": "bandhit0001",
                            "title": "Artist Extra",
                            "artist": "Local Band",
                            "duration": 215,
                        }
                    ]
                }

        fake_yt_dlp.YoutubeDL = FakeMixYdl
        sys.modules["yt_dlp"] = fake_yt_dlp

        payload = json.dumps(
            {
                "seedTracks": [
                    {
                        "trackId": "local_1",
                        "videoId": "",
                        "title": "Local Song",
                        "artist": "Local Band",
                    },
                    {
                        "trackId": "yt_stream76543",
                        "videoId": "stream76543",
                        "title": "Stream Song",
                        "artist": "Acoustic Hero",
                    },
                ],
                "seedArtists": [
                    {"name": "Local Band", "weight": 9.0},
                    {"name": "Acoustic Hero", "weight": 7.0},
                ],
                "recentQueries": ["indie acoustic"],
                "excludeVideoIds": ["skip9999999"],
                "preferredDurationMs": 210000,
            }
        )

        rec = json.loads(aura_yt_engine.fetch_explore_recommendations(payload, limit=12))
        self.assertTrue(rec["ok"])
        self.assertEqual(
            rec["resolvedSeeds"],
            [{"trackId": "local_1", "videoId": "seed1234567"}],
        )
        for_you_ids = [item["videoId"] for item in rec["forYou"]]
        self.assertIn("mixtrack001", for_you_ids)
        self.assertIn("mixtrack002", for_you_ids)
        self.assertNotIn("skip9999999", for_you_ids)
        self.assertNotIn("podcast0001", for_you_ids)
        self.assertNotIn("seed1234567", for_you_ids)
        self.assertTrue(rec["becauseLabel"].startswith("Porque escuchaste"))
        disc_ids = [item["videoId"] for item in rec["discoveryItems"]]
        self.assertIn("disc0000001", disc_ids)


if __name__ == "__main__":
    unittest.main()
