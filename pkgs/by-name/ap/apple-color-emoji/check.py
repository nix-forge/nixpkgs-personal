"""Validate color artwork and Apple AAT composition against Unicode test data."""

import argparse
import json
from pathlib import Path

import uharfbuzz as hb
from fontTools.ttLib import TTFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("font", type=Path)
    parser.add_argument("emoji_data", type=Path)
    parser.add_argument("--original", type=Path)
    args = parser.parse_args()
    font = TTFont(args.font)
    if args.original:
        original = TTFont(args.original)
        for tag in ["morx", "GDEF", "GPOS", "cmap", "hmtx", "name"]:
            if original.getTableData(tag) != font.getTableData(tag):
                raise ValueError(f"Changed original shaping or identity table: {tag}")
        for source, target in zip(
            original["CBDT"].strikeData, font["CBDT"].strikeData, strict=True
        ):
            for name, bitmap in source.items():
                if (
                    bitmap.imageData != target[name].imageData
                    or bitmap.metrics.__dict__ != target[name].metrics.__dict__
                ):
                    raise ValueError(f"Changed original Apple artwork: {name}")
    required = {"CBDT", "CBLC", "morx", "GDEF", "GPOS"}
    if not required.issubset(font.keys()):
        raise ValueError("Missing color or shaping tables")
    if font["name"].getDebugName(6) != "AppleColorEmoji":
        raise ValueError("Unexpected font identity")
    sizes = [strike.bitmapSizeTable.ppemY for strike in font["CBLC"].strikes]  # ty: ignore[unresolved-attribute] -- fontTools populates ppemY from the binary EBLC structure.
    if sizes != [20, 26, 32, 40, 48, 52, 64, 96]:
        raise ValueError(f"Unexpected bitmap sizes: {sizes}")
    shaper = hb.Font(hb.Face(args.font.read_bytes()))
    order = font.getGlyphOrder()
    total = composed = 0
    failures = []
    for line in args.emoji_data.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        code, rest = line.split(";", 1)
        status, description = rest.split("#", 1)
        if status.strip() not in {"fully-qualified", "component"}:
            continue
        buffer = hb.Buffer()
        buffer.add_str("".join(chr(int(value, 16)) for value in code.split()))
        buffer.guess_segment_properties()
        buffer.flags = hb.BufferFlags.REMOVE_DEFAULT_IGNORABLES
        hb.shape(shaper, buffer)
        glyphs = [info.codepoint for info in buffer.glyph_infos]
        positions = buffer.glyph_positions
        valid = bool(glyphs) and 0 not in glyphs
        valid &= sum(p.x_advance for p in positions) == shaper.face.upem
        # Apple composes some mixed-tone emoji from two bitmap layers, with
        # the second positioned over the first. Do not require a single glyph.
        valid &= len(glyphs) in {1, 2}
        if len(glyphs) == 2:
            composed += 1
            valid &= positions[1].x_advance == 0
            valid &= positions[1].x_offset == -positions[0].x_advance
        for strike in font["CBDT"].strikeData:
            for glyph in glyphs:
                bitmap = strike.get(order[glyph])
                valid &= bitmap is not None and bitmap.imageData.startswith(
                    b"\x89PNG\r\n\x1a\n"
                )
        if not valid:
            failures.append(description.strip())
        total += 1
    if total != 3953 or failures:
        raise ValueError(f"Validated {total} entries; failures: {failures}")
    print(json.dumps({"total": total, "composed": composed, "failures": failures}))


if __name__ == "__main__":
    main()
