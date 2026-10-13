"""Regression checks for versioned release provenance."""

import io
import unittest
from unittest.mock import patch
from urllib.request import HTTPRedirectHandler

from update import fetch_json, source_entry


class SourceTests(unittest.TestCase):
    def release(self):
        return {
            "tag_name": "macos-26-20260722-484daf4e",
            "assets": [
                {
                    "name": "AppleColorEmoji-Linux.ttf",
                    "digest": "sha256:" + "ab" * 32,
                    "browser_download_url": "https://github.com/samuelngs/apple-emoji-ttf/releases/download/macos-26-20260722-484daf4e/AppleColorEmoji-Linux.ttf",
                }
            ],
        }

    def test_versioned_asset(self):
        entry = source_entry(self.release(), "a" * 40)
        self.assertEqual(entry["version"], "26-20260722-484daf4e")
        self.assertEqual(entry["files"][0]["sha256"], "ab" * 32)

    def test_moving_asset_rejected(self):
        release = self.release()
        release["assets"][0]["browser_download_url"] = (
            "https://github.com/samuelngs/apple-emoji-ttf/releases/latest/download/AppleColorEmoji-Linux.ttf"
        )
        with self.assertRaises(ValueError):
            source_entry(release, "a" * 40)

    def test_missing_digest_rejected(self):
        release = self.release()
        del release["assets"][0]["digest"]
        with self.assertRaises(ValueError):
            source_entry(release, "a" * 40)


class RequestTests(unittest.TestCase):
    def request(self, url, env):
        with (
            patch.dict("os.environ", env, clear=True),
            patch(
                "update.urlopen", return_value=io.BytesIO(b'{"ok": true}')
            ) as open_url,
        ):
            self.assertEqual(fetch_json(url), {"ok": True})
        return open_url.call_args.args[0]

    def test_native_actions_token_authenticates_exact_github_api(self):
        for url in (
            "https://api.github.com/repos/samuelngs/apple-emoji-ttf/releases/latest",
            "https://api.github.com:443/repos/samuelngs/apple-emoji-ttf/commits/tag",
        ):
            with self.subTest(url=url):
                request = self.request(url, {"GITHUB_TOKEN": "fixture-token"})
                self.assertEqual(
                    request.get_header("Authorization"), "Bearer fixture-token"
                )

    def test_cli_token_precedence_and_no_token_public_fallback(self):
        url = "https://api.github.com/repos/example/project/releases/latest"
        request = self.request(url, {"GH_TOKEN": "cli", "GITHUB_TOKEN": "actions"})
        self.assertEqual(request.get_header("Authorization"), "Bearer cli")
        self.assertIsNone(self.request(url, {}).get_header("Authorization"))

    def test_other_origins_and_userinfo_never_receive_token(self):
        for url in (
            "http://api.github.com/repos/example/project",
            "https://api.github.com:444/repos/example/project",
            "https://api.github.com.example.org/project",
            "https://github.com/example/project/releases/download/font.ttf",
            "https://example.org/project",
            "https://user@api.github.com/repos/example/project",
        ):
            with self.subTest(url=url):
                self.assertIsNone(
                    self.request(url, {"GITHUB_TOKEN": "fixture-token"}).get_header(
                        "Authorization"
                    )
                )

    def test_real_redirect_handler_never_forwards_authorization(self):
        request = self.request(
            "https://api.github.com/repos/example/project/releases/latest",
            {"GITHUB_TOKEN": "fixture-token"},
        )
        self.assertEqual(request.get_header("Authorization"), "Bearer fixture-token")
        for destination in (
            "https://example.org/stolen",
            "http://api.github.com/repos/example/project",
            "https://api.github.com:444/repos/example/project",
            "https://api.github.com/repos/example/renamed",
        ):
            with self.subTest(destination=destination):
                redirected = HTTPRedirectHandler().redirect_request(
                    request, None, 302, "Found", {}, destination
                )
                self.assertIsNone(redirected.get_header("Authorization"))


if __name__ == "__main__":
    unittest.main()
