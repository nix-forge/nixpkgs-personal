"""Represent emoji presentation with cmap variation sequences, not ligatures.

Browsers select fonts before shaping. A blank base-character cmap entry with
an FE0F ligature can make Gecko split custom emoji across font runs, even when
shaping the entire sequence directly with HarfBuzz succeeds. Map base artwork
and Unicode variation sequences first, then compose the remaining characters.
"""

import sys
from pathlib import Path

import uharfbuzz as hb
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable


def normalize(path: Path, artwork: Path) -> None:
    font = TTFont(path, recalcTimestamp=False)
    shaper = hb.Font(hb.Face(path.read_bytes()))
    mappings = {}
    variation_bases = set()
    for source in sorted(artwork.glob("*.svg")):
        codepoints = tuple(int(cp, 16) for cp in source.stem.split("-"))
        normalized = tuple(cp for cp in codepoints if cp != 0xFE0F)
        buffer = hb.Buffer()
        buffer.add_str("".join(map(chr, codepoints)))
        buffer.guess_segment_properties()
        hb.shape(shaper, buffer)
        assert len(buffer.glyph_infos) == 1, source.name
        assert buffer.glyph_infos[0].codepoint != 0, source.name
        glyph = font.getGlyphName(buffer.glyph_infos[0].codepoint)
        assert normalized not in mappings, f"Ambiguous encoding: {source.name}"
        mappings[normalized] = glyph
        for index, cp in enumerate(codepoints):
            if cp == 0xFE0F:
                assert index > 0, source.name
                variation_bases.add(codepoints[index - 1])

    for table in font["cmap"].tables:
        if table.isUnicode() and table.format != 14:
            for sequence, glyph in mappings.items():
                if len(sequence) == 1 and (
                    sequence[0] <= 0xFFFF or table.format in {12, 13}
                ):
                    table.cmap[sequence[0]] = glyph
    cmap = font.getBestCmap()
    if cmap is None:
        raise ValueError("The compiled emoji font has no Unicode character map")
    assert variation_bases <= cmap.keys()
    assert not any(table.format == 14 for table in font["cmap"].tables)
    variations = CmapSubtable.newSubtable(14)
    variations.platformID = 0
    variations.platEncID = 5
    variations.language = 0
    variations.cmap = {}
    variations.uvsDict = {0xFE0F: [(cp, None) for cp in sorted(variation_bases)]}
    font["cmap"].tables.append(variations)

    features = [
        "languagesystem DFLT dflt;",
        "languagesystem latn dflt;",
        "feature ccmp {",
    ]
    for sequence, glyph in sorted(
        mappings.items(), key=lambda item: (-len(item[0]), item[0])
    ):
        if len(sequence) > 1:
            components = " ".join(cmap[cp] for cp in sequence)
            features.append(f"sub {components} by {glyph};")
    features.append("} ccmp;")
    del font["GSUB"]
    addOpenTypeFeaturesFromString(font, "\n".join(features))
    font.save(path)
    print(
        f"Normalized {len(mappings)} encodings with "
        f"{len(variation_bases)} emoji variation bases."
    )


if __name__ == "__main__":
    normalize(Path(sys.argv[1]), Path(sys.argv[2]))
