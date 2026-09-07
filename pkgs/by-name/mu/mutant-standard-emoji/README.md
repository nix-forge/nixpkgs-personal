# Mutant Standard Emoji

Optional COLRv1 font built from the official Mutant Standard 2024.06 codepoint
SVG archive using upstream nixpkgs' nanoemoji. Family: `Mutant Standard Emoji`.
This is a font build maintained in nixpkgs-personal, not an official upstream
font release. It does not install Fontconfig aliases or change default fonts.

Artwork by Caius Nocturne, licensed CC BY-NC-SA 4.0 International.
The original license notice and both credit files accompany the font. The font
embeds attribution, the license URL, and the build identity. Redistribution and
adaptations must retain attribution and comply with the noncommercial and
share-alike terms. See <https://mutant.tech> and
<https://creativecommons.org/licenses/by-nc-sa/4.0/>.

The build converts SVG pixel lengths to equivalent unitless coordinates for
picosvg and compiles paths, colors, clipping and gradients into COLRv1. It neither
redraws glyphs nor assigns unrelated artwork to missing characters.

Install checks shape all 7,829 supplied encodings through
HarfBuzz and require a single visible COLR glyph for each. These checks cover
the supplied set, not all Unicode emoji. Mutant Standard intentionally omits
some Unicode emoji and adds Private Use Area characters. Keep a complete font
such as Noto Color Emoji as the normal fallback. Images without codepoints
cannot be accessed as text through this font.

Requires a renderer supporting COLRv1. This format avoids the discontinued
Forc build tool and bitmap scaling. The unrelated historical sbix download in
April93/EmojiTest is unaffected by installing this font.

Update the pinned artwork hash after reviewing upstream
changes. Rerun the shaping checks and visually compare browser output with the
source artwork. No automatic updater is provided.
