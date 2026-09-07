"""Regression checks for versioned release provenance."""

import unittest

from update import source_entry


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


if __name__ == "__main__":
    unittest.main()
