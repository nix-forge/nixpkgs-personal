"""Check every supplied encoding through HarfBuzz and the final COLR table."""

import sys
from pathlib import Path

import uharfbuzz as hb
from fontTools.ttLib import TTFont

path, artwork = map(Path, sys.argv[1:])
font = TTFont(path)
assert font["name"].getDebugName(1) == "Mutant Standard Emoji"
assert font["COLR"].version == 1
assert font["CPAL"].palettes
color_glyphs = {
    record.BaseGlyph for record in font["COLR"].table.BaseGlyphList.BaseGlyphPaintRecord
}
shaper = hb.Font(hb.Face(path.read_bytes()))
failures = []
sources = sorted(artwork.glob("*.svg"))
assert len(sources) == 7829, len(sources)
for source in sources:
    text = "".join(chr(int(cp, 16)) for cp in source.stem.split("-"))
    buffer = hb.Buffer()
    buffer.add_str(text)
    buffer.guess_segment_properties()
    hb.shape(shaper, buffer)
    glyphs = [info.codepoint for info in buffer.glyph_infos]
    if (
        len(glyphs) != 1
        or glyphs[0] == 0
        or font.getGlyphName(glyphs[0]) not in color_glyphs
        or buffer.glyph_positions[0].x_advance <= 0
    ):
        failures.append(source.stem)
assert not failures, f"Broken source encodings ({len(failures)}): {failures[:30]}"
print(f"All {len(sources)} upstream encodings shape to one color glyph.")
