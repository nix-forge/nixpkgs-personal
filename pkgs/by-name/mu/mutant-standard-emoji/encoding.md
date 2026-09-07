# Browser shaping

The SVG filenames include U+FE0F, the emoji presentation selector. Nanoemoji
initially compiles these as ordinary multi-character ligatures. That leaves
some base characters with blank cmap entries. Gecko may choose another font
for the base before shaping, breaking a custom sequence into separate symbols.
A direct HarfBuzz check on the whole string does not catch that font-selection
step.

The final encoding pass maps base characters to their existing artwork, adds
standard cmap format 14 emoji variation sequences, and rebuilds composition
rules without FE0F. No artwork or private-use encoding is reassigned. Ambiguous
selector-normalized source encodings fail the build rather than silently
overwriting a glyph. This is a general correction across the supplied set.

Both compilation and final installation check all 7,829 source encodings with
HarfBuzz. The browser regression additionally checks the advance of every
source sequence in Zen, catching sequences split across fonts or glyphs. It
also saves a visual sample for comparison with the original SVGs.

Vector compilation is a separate cached derivation because it is expensive;
changing the encoding pass does not need to repeat SVG conversion.
