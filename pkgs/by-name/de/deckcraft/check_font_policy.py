"""Check shipped DeckCraft binaries exclude the forbidden vendor emoji faces."""

import sys
from pathlib import Path


def check(package: Path, vendor: Path) -> None:
    """Inspect the actual GUI/CLI bytes, including stripped and signed binaries.

    Raises:
        ValueError: If an emoji blob remains embedded or fallback data is missing.

    """
    font_roots = list(vendor.glob("epaint_default_fonts-*/fonts"))
    if len(font_roots) != 1:
        raise ValueError("Expected one pinned epaint font bundle")
    font_root = font_roots[0]
    forbidden = [font_root / "NotoEmoji-Regular.ttf", font_root / "emoji-icon-font.ttf"]
    fallback = (font_root / "Ubuntu-Light.ttf").read_bytes()
    for command in ("deckcraft", "deckcraft-cli"):
        path = package / "bin" / command
        wrapped = path.with_name(f".{command}-wrapped")
        binary = (wrapped if wrapped.exists() else path).read_bytes()
        for font in forbidden:
            if font.read_bytes() in binary:
                raise ValueError(f"Forbidden vendor font in {command}: {font.name}")
        if fallback not in binary:
            raise ValueError(f"Missing approved last-resort face: {command}")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]))
