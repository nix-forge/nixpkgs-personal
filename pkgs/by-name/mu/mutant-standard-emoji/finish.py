"""Embed provenance and license in the compiled font, with stable timestamps."""

import sys

from fontTools.ttLib import TTFont

path, version = sys.argv[1:]
font = TTFont(path, recalcTimestamp=False)
records = {
    0: "Mutant Standard artwork by Caius Nocturne (https://nocturne.works).",
    3: f"MutantStandardEmoji-{version}-COLRv1-nixpkgs-personal",
    5: f"Version {version}; COLRv1 build by nixpkgs-personal",
    8: "Mutant Standard",
    9: "Caius Nocturne",
    10: "Optional color emoji font compiled from Mutant Standard codepoint SVGs. "
    "Includes project-specific Private Use Area encodings.",
    11: "https://mutant.tech",
    13: "Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International",
    14: "https://creativecommons.org/licenses/by-nc-sa/4.0/",
}
for name_id, value in records.items():
    font["name"].setName(value, name_id, 3, 1, 0x409)
# OpenType uses seconds since 1904. Use the release month for both timestamps.
font["head"].created = font["head"].modified = 3800044800  # ty: ignore[unresolved-attribute] -- fontTools populates head fields dynamically from its binary structure.
font.save(path)
