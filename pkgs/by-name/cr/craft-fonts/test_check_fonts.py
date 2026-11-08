"""Exercise font provenance validation with independent manifest fixtures."""

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "check_fonts", Path(__file__).with_name("check_fonts.py")
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Cannot load font validator")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class FontValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "fonts").mkdir()
        self.font = self.root / "fonts/test.ttf"
        self.font.write_bytes(b"immutable-font-fixture")
        (self.root / "fonts/OFL.txt").write_text("SIL OPEN FONT LICENSE Version 1.1")
        self.manifest = self.root / "fonts/manifest.txt"
        self.write_manifest()

    def write_manifest(self, filename="fonts/test.ttf", license_name="OFL-1.1"):
        checksum = hashlib.sha256(b"immutable-font-fixture").hexdigest()
        self.manifest.write_text(
            f"Fixture | Regular | {filename} | Latn | {license_name} | "
            f"fonts/OFL.txt | {checksum} | https://example.org/source\n"
        )

    def test_valid_manifest(self):
        VALIDATOR.check(self.root)

    def test_modified_font_rejected(self):
        self.font.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            VALIDATOR.check(self.root)

    def test_path_escape_rejected(self):
        self.write_manifest(filename="../outside.ttf")
        with self.assertRaisesRegex(ValueError, "escapes source"):
            VALIDATOR.check(self.root)

    def test_symlink_escape_rejected(self):
        self.font.unlink()
        self.font.symlink_to(self.root.parent / "outside.ttf")
        with self.assertRaisesRegex(ValueError, "escapes source"):
            VALIDATOR.check(self.root)

    def test_empty_manifest_rejected(self):
        self.manifest.write_text("# no fonts\n")
        with self.assertRaisesRegex(ValueError, "empty"):
            VALIDATOR.check(self.root)

    def test_license_change_rejected(self):
        self.write_manifest(license_name="unreviewed")
        with self.assertRaisesRegex(ValueError, "Unexpected font metadata"):
            VALIDATOR.check(self.root)

    def test_missing_license_text_rejected(self):
        (self.root / "fonts/OFL.txt").write_text("not a license")
        with self.assertRaisesRegex(ValueError, "Missing OFL"):
            VALIDATOR.check(self.root)


if __name__ == "__main__":
    unittest.main()
