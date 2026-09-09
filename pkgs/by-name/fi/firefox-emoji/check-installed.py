"""Validate the installed package assets."""

import sys

from fontTools.ttLib import TTFont

with TTFont(sys.argv[1]) as font:
    sample = "😀😁😂😃😄😅😆😇😈😉😊😋😌😍"
    cmap = font.getBestCmap()
    assert cmap is not None
    assert all(
        ord(char) in cmap and font.getGlyphID(cmap[ord(char)]) for char in sample
    )
    assert font["COLR"].version == 0
    assert font["CPAL"].palettes
    assert all(cmap[ord(char)] in font["COLR"].ColorLayers for char in sample)
