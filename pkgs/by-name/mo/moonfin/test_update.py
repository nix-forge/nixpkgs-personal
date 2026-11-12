"""Exercise release identity and pinned Git source checks."""

from __future__ import annotations

import base64
import unittest
from unittest.mock import patch

import update


class UpdateTests(unittest.TestCase):
    def test_flutter_builder_tracks_lock_constraint(self) -> None:
        update.check_flutter_sdk({"sdks": {"flutter": ">=3.47.0"}})
        with self.assertRaisesRegex(ValueError, "update linux.nix builder"):
            update.check_flutter_sdk({"sdks": {"flutter": ">=3.50.0"}})

    def test_asset_digest_must_belong_to_selected_release(self) -> None:
        digest = "12" * 32
        asset = {
            "name": "Moonfin_macOS_v2.7.0.dmg",
            "browser_download_url": "https://github.com/Moonfin-Client/Moonfin-Core/releases/download/2.7.0/Moonfin_macOS_v2.7.0.dmg",
            "digest": f"sha256:{digest}",
        }
        url, hash_value = update.asset_hash({"assets": [asset]}, "2.7.0")
        self.assertEqual(url, asset["browser_download_url"])
        self.assertEqual(
            hash_value, "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode()
        )
        with self.assertRaisesRegex(ValueError, "expected one macOS asset"):
            update.asset_hash({"assets": [asset]}, "2.8.0")

    def test_asset_url_rejects_other_origin_and_interpolation(self) -> None:
        for url in (
            "https://example.invalid/moonfin.dmg",
            "https://github.com/${unexpected}",
        ):
            asset = {
                "name": "Moonfin_macOS_v2.7.0.dmg",
                "browser_download_url": url,
                "digest": "sha256:" + "12" * 32,
            }
            with self.assertRaisesRegex(
                ValueError, "exact selected GitHub release URL"
            ):
                update.asset_hash({"assets": [asset]}, "2.7.0")

    def test_git_dependencies_share_one_fetch_for_one_commit(self) -> None:
        description = {
            "url": "https://github.com/example/media-kit.git",
            "resolved-ref": "a" * 40,
        }
        lock = {
            "packages": {
                "first": {"source": "git", "description": description},
                "second": {"source": "git", "description": description},
            }
        }
        with patch.object(
            update, "prefetch", return_value={"hash": "sha256-test"}
        ) as fetch:
            self.assertEqual(
                update.git_hashes(lock),
                {"first": "sha256-test", "second": "sha256-test"},
            )
        fetch.assert_called_once()
        description["url"] = "https://example.invalid/media-kit.git"
        with self.assertRaisesRegex(ValueError, "not a GitHub repository"):
            update.git_hashes(lock)


if __name__ == "__main__":
    unittest.main()
