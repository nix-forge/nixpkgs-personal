"""Validate the installed package assets."""

import configparser
import sys
from pathlib import Path
from typing import cast

from PIL import Image

renders, icons = map(Path, sys.argv[1:])
theme = configparser.ConfigParser()
theme.read(icons / "index.theme")
assert theme["Icon Theme"]["Inherits"].split(",") == ["Papirus-Dark", "hicolor"]
assert theme["scalable/apps"]["Context"] == "Applications"
for icon in ("chatgpt", "zen-browser", "vscode"):
    for size in (16, 24, 32, 42, 84):
        with Image.open(renders / f"{icon}-{size}.png") as image:
            image = image.convert("RGBA")
            assert image.size == (size, size)
            pixels = cast(
                list[tuple[int, int, int, int]], list(image.get_flattened_data())
            )
            opaque = [(r, g, b) for r, g, b, a in pixels if a > 240]
            assert len(opaque) > size * size * 0.4, (icon, "missing artwork")
            assert pixels[0][3] == 0, (icon, "opaque canvas")
            dark = sum(max(rgb) < 100 for rgb in opaque)
            visible = sum(max(rgb) > 150 for rgb in opaque)
            assert dark > len(opaque) * 0.3, (icon, "background is not dark")
            assert visible > len(opaque) * 0.05, (icon, "logo lacks contrast")
            if icon == "zen-browser":
                assert any(r > 180 and r > g * 1.5 for r, g, b in opaque)
            if icon == "vscode":
                assert any(b > 100 and b > r * 1.5 for r, g, b in opaque)
