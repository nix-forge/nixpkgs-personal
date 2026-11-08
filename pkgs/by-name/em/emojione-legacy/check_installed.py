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
    documents = font["SVG "].docList
    assert documents
    assert all(
        any(
            doc.startGlyphID <= font.getGlyphID(cmap[ord(char)]) <= doc.endGlyphID
            for doc in documents
        )
        for char in sample
    )
