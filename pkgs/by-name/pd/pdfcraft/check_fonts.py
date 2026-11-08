"""Verify PdfCraft's selected font bytes and Chinese catalog outline coverage."""

import hashlib
import sys
from pathlib import Path

from fontTools.ttLib import TTFont


def check(root: Path, catalogs: Path) -> None:
    """Reject changed fonts, omitted notices and prohibited faces.

    Raises:
        ValueError: If font policy, hash, notice or glyph checks fail.

    """
    chinese = None
    rows = [
        line
        for line in (root / "fonts/manifest.txt").read_text().splitlines()
        if line and not line.startswith("#")
    ]
    if len(rows) != 7:
        raise ValueError("Expected seven policy-compliant faces")
    for row in rows:
        family, _, filename, _, licence, notice, checksum, _ = row.split(" | ")
        if "CJK" in family or "Source Han" in family:
            raise ValueError(f"Prohibited font: {family}")
        font = root / filename
        if hashlib.sha256(font.read_bytes()).hexdigest() != checksum:
            raise ValueError(f"Font checksum mismatch: {filename}")
        terms = (root / notice).read_text()
        expected = "SIL OPEN FONT LICENSE" if licence == "OFL-1.1" else "Apache License"
        if expected not in terms:
            raise ValueError(f"Missing complete licence: {notice}")
        if family == "Droid Sans Fallback":
            chinese = font
    if chinese is None or any("noto-sans-cjk" in str(path) for path in root.rglob("*")):
        raise ValueError("Incorrect CJK font selection")
    check_catalogs(chinese, catalogs)
    check_thai(root / "fonts/noto-sans-thai/NotoSansThai.ttf")


def check_catalogs(chinese: Path, catalogs: Path) -> None:
    """Require nonempty outlines for both Chinese interface catalogs.

    Raises:
        ValueError: If a catalog is empty or a Han glyph has no outline.

    """
    with TTFont(chinese) as font:
        cmap = font.getBestCmap()
        if cmap is None:
            raise ValueError("Droid font has no Unicode cmap")
        for language in ("zh-hans", "zh-hant"):
            text = (catalogs / f"{language}.tsv").read_text()
            han = {ord(char) for char in text if 0x3400 <= ord(char) <= 0x9FFF}
            if not han:
                raise ValueError(f"Empty Chinese catalog: {language}")
            for codepoint in han:
                glyph_name = cmap.get(codepoint)
                if glyph_name is None:
                    raise ValueError(f"Missing {language} glyph U+{codepoint:04X}")
                glyph = font["glyf"][glyph_name]
                if (
                    glyph.numberOfContours == 0
                    or glyph.xMax <= glyph.xMin
                    or glyph.yMax <= glyph.yMin
                ):
                    raise ValueError(f"Empty {language} glyph U+{codepoint:04X}")


def check_thai(path: Path) -> None:
    """Require drawn outlines for representative Thai filenames, including vowel marks.

    Raises:
        ValueError: If a Thai filename character has no usable outline.

    """
    with TTFont(path) as font:
        cmap = font.getBestCmap()
        if cmap is None:
            raise ValueError("Thai face has no Unicode cmap")
        for character in set("เปิดไฟล์บันทึก"):
            glyph_name = cmap.get(ord(character))
            if glyph_name is None:
                raise ValueError(f"Missing Thai glyph U+{ord(character):04X}")
            glyph = font["glyf"][glyph_name]
            if (
                glyph.numberOfContours == 0
                or glyph.xMax <= glyph.xMin
                or glyph.yMax <= glyph.yMin
            ):
                raise ValueError(f"Empty Thai glyph U+{ord(character):04X}")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]))
