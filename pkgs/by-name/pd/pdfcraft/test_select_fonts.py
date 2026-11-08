"""Exercise policy selection with an upstream-style manifest containing Thai."""

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "select_fonts", Path(__file__).with_name("select_fonts.py")
)
assert SPEC is not None
assert SPEC.loader is not None
SELECTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SELECTOR)


class FontSelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "upstream"
        self.source.mkdir()
        self.output = self.root / "selected"
        self.rows = []
        for index, family in enumerate([
            "Shippori Mincho",
            "BIZ UDPGothic",
            "BIZ UDPGothic",
            "BIZ UDMincho",
            "Noto Sans Arabic",
            "Noto Sans CJK SC",
        ]):
            font = self.source / f"face-{index}.ttf"
            font.write_bytes(f"independent-face-{index}".encode())
            checksum = hashlib.sha256(font.read_bytes()).hexdigest()
            self.rows.append(
                f"{family} | Regular | {font.name} | Latn | OFL-1.1 | "
                f"OFL.txt | {checksum} | https://example.org/font-source"
            )
        (self.source / "OFL.txt").write_text("SIL OPEN FONT LICENSE")
        for name in ["LICENSE-MIT", "LICENSE-APACHE"]:
            (self.source / name).write_text(f"Complete {name} fixture")
        self.font = self.root / "independent.ttf"
        self.font.write_bytes(b"independently-reviewed-font")
        self.notice = self.root / "NOTICE"
        self.notice.write_text("Complete independently-reviewed licence")
        self.files = SELECTOR.FontFiles(self.font, self.notice)
        font_hash = hashlib.sha256(self.font.read_bytes()).hexdigest()
        notice_hash = hashlib.sha256(self.notice.read_bytes()).hexdigest()
        fixture_hashes = patch.multiple(
            SELECTOR,
            DROID_HASH=font_hash,
            DROID_NOTICE_HASH=notice_hash,
            THAI_HASH=font_hash,
            THAI_NOTICE_HASH=notice_hash,
        )
        fixture_hashes.start()
        self.addCleanup(fixture_hashes.stop)
        self.rows.append(
            "Noto Sans Thai | Regular | upstream-thai.ttf | Thai | OFL-1.1 | "
            f"OFL.txt | {font_hash} | https://example.org/thai-source"
        )
        (self.source / "fonts").mkdir()

    def select(self) -> None:
        (self.source / "fonts/manifest.txt").write_text("\n".join(self.rows) + "\n")
        SELECTOR.select(self.source, self.files, self.files, self.output, "a" * 40)

    def test_latest_manifest_selects_thai_once_and_current_provenance(self) -> None:
        self.select()
        rows = (self.output / "fonts/manifest.txt").read_text().splitlines()[1:]
        self.assertEqual(len(rows), 7)
        self.assertEqual(sum(row.startswith("Noto Sans Thai |") for row in rows), 1)
        self.assertFalse(any("Noto Sans CJK" in row for row in rows))
        self.assertEqual(
            (self.output / "fonts/noto-sans-thai/NotoSansThai.ttf").read_bytes(),
            self.font.read_bytes(),
        )
        self.assertIn("/tree/" + "a" * 40, (self.output / "ATTRIBUTION.md").read_text())

    def test_changed_upstream_thai_face_requires_review(self) -> None:
        self.rows[-1] = self.rows[-1].replace(SELECTOR.THAI_HASH, "0" * 64)
        with self.assertRaisesRegex(ValueError, "Unreviewed font"):
            self.select()

    def test_additional_unreviewed_family_is_rejected(self) -> None:
        self.rows.append(self.rows[0].replace("Shippori Mincho", "New Family"))
        with self.assertRaisesRegex(ValueError, "Unreviewed font"):
            self.select()


if __name__ == "__main__":
    unittest.main()
