"""Fill missing RGI artwork from Noto without changing existing Apple glyphs."""

import argparse
import hashlib
import io
import json
from copy import deepcopy
from pathlib import Path

import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import C_B_D_T_, E_B_L_C_
from PIL import Image


def shape(font, text):
    buffer = hb.Buffer()
    buffer.add_str(text)
    buffer.guess_segment_properties()
    buffer.flags = hb.BufferFlags.REMOVE_DEFAULT_IGNORABLES
    hb.shape(font, buffer)
    return [info.codepoint for info in buffer.glyph_infos]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("font", type=Path)
    parser.add_argument("fallback", type=Path)
    parser.add_argument("emoji_data", type=Path)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    font = TTFont(args.font, recalcTimestamp=False)
    fallback = TTFont(args.fallback)
    shaper = hb.Font(hb.Face(args.font.read_bytes()))
    fallback_shaper = hb.Font(hb.Face(args.fallback.read_bytes()))
    order = font.getGlyphOrder()
    fallback_order = fallback.getGlyphOrder()
    repairs = {}
    for line in args.emoji_data.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        code, rest = line.split(";", 1)
        status, _ = rest.split("#", 1)
        if status.strip() not in {"fully-qualified", "component"}:
            continue
        text = "".join(chr(int(value, 16)) for value in code.split())
        glyphs = shape(shaper, text)
        missing = [
            g
            for g in glyphs
            if any(order[g] not in strike for strike in font["CBDT"].strikeData)
        ]
        if not missing:
            continue
        donor = shape(fallback_shaper, text)
        if len(glyphs) != 1 or len(donor) != 1 or 0 in glyphs or 0 in donor:
            raise ValueError(f"Cannot supplement composed or missing glyph: {code}")
        name = order[glyphs[0]]
        donor_name = fallback_order[donor[0]]
        if name in repairs and repairs[name]["donor"] != donor_name:
            raise ValueError(f"Ambiguous fallback for {name}")
        repairs[name] = {"code": code.strip(), "donor": donor_name}
    donor_data = fallback["CBDT"].strikeData[-1]
    for strike, data in zip(font["CBLC"].strikes, font["CBDT"].strikeData, strict=True):
        ppem = strike.bitmapSizeTable.ppemY  # ty: ignore[unresolved-attribute] -- fontTools populates ppemY from the binary EBLC structure.
        for name, repair in repairs.items():
            if name in data:
                continue
            source = donor_data[repair["donor"]]
            bitmap = C_B_D_T_.cbdt_bitmap_format_17(None, font)
            bitmap.metrics = deepcopy(source.metrics)
            scale = ppem / source.metrics.Advance
            for field in ["height", "width", "BearingX", "BearingY", "Advance"]:
                setattr(
                    bitmap.metrics, field, round(getattr(source.metrics, field) * scale)
                )
            im = Image.open(io.BytesIO(source.imageData)).convert("RGBA")
            im = im.resize(
                (bitmap.metrics.width, bitmap.metrics.height), Image.Resampling.LANCZOS
            )
            png = io.BytesIO()
            im.save(png, format="PNG")
            bitmap.imageData = png.getvalue()
            data[name] = bitmap
            index = E_B_L_C_.eblc_index_sub_table_1(None, font)
            index.indexFormat = 1
            index.imageFormat = 17
            index.names = [name]
            glyph_id = font.getGlyphID(name)
            index.firstGlyphIndex = index.lastGlyphIndex = glyph_id
            # Existing ranges may contain unused glyph IDs. A singleton must
            # not overlap them; refuse a source update that needs repartitioning.
            if any(
                t.firstGlyphIndex <= glyph_id <= t.lastGlyphIndex
                for t in strike.indexSubTables
            ):
                raise ValueError(
                    f"Fallback would overlap an existing bitmap range: {name}"
                )
            strike.indexSubTables.append(index)
        strike.indexSubTables.sort(key=lambda index: index.firstGlyphIndex)
    if "DSIG" in font:
        del font["DSIG"]  # Source signatures cannot describe modified tables.
    font.save(args.font)
    with args.fallback.open("rb") as stream:
        fallback_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    with args.font.open("rb") as stream:
        installed_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    args.report.write_text(
        json.dumps(
            {
                "fallback": "Noto Color Emoji",
                "fallbackVersion": fallback["name"].getDebugName(5),
                "fallbackSha256": fallback_hash,
                "installedSha256": installed_hash,
                "repairs": repairs,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
