"""Check that Windows inventory validation rejects changed or missing payloads."""

import os
import shutil
import tempfile
import unittest
from pathlib import Path

from font_manifest import manifest, validate


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.font = self.root / "fixture.ttf"
        shutil.copyfile(os.environ["FONT_FIXTURE"], self.font)
        self.expected = manifest(self.root, "fixture-1")

    def test_unchanged_payload(self):
        validate(self.root, self.expected)

    def test_changed_bytes(self):
        with self.font.open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaises(ValueError):
            validate(self.root, self.expected)

    def test_wrong_identity(self):
        self.expected["files"][0]["faces"] = ["Wrong-Face"]
        with self.assertRaises(ValueError):
            validate(self.root, self.expected)

    def test_missing_file(self):
        self.font.unlink()
        with self.assertRaises(ValueError):
            validate(self.root, self.expected)

    def test_unexpected_font(self):
        shutil.copyfile(self.font, self.root / "unexpected.ttf")
        with self.assertRaises(ValueError):
            validate(self.root, self.expected)


if __name__ == "__main__":
    unittest.main()
