# Apple Color Emoji for Linux

This package installs the Linux font from the versioned
[macos-26-20260722-484daf4e release](https://github.com/samuelngs/apple-emoji-ttf/releases/tag/macos-26-20260722-484daf4e)
of samuelngs/apple-emoji-ttf. It is a third-party conversion of Apple's font,
not an Apple-hosted download. The release uses CBDT/CBLC color bitmap tables
with eight sizes from 20 to 96 pixels and retains Apple AAT shaping tables.

The versioned URL, SHA-256,
payload hash and PostScript face are recorded in source.json. Builds verify
downloaded bytes and do not contact a moving release endpoint,
execute installers, or require a private Mac export. The font is installed
with its existing artwork and shaping preserved. Upstream's Fontconfig replacement rules are not
installed; applications can request the Apple Color Emoji family explicitly.

The release advertises three standalone symbols with no artwork: female sign,
male sign and medical symbol. `repair.py` discovers missing artwork by shaping
Unicode 17's RGI sequences, then fills only empty bitmap slots from the pinned
nixpkgs Noto Color Emoji font. It has no list of special-cased codepoints. All
eight bitmap sizes are generated with Lanczos resampling. Existing Apple ONGs,
metrics, character maps and shaping tables are checked for exact preservation.
Keeping those character mappings is necessary for AAT profession and gender
sequences; simply deleting empty mappings would break combined emoji.

`artwork-repairs.json` identifies each supplemented glyph. These three standalone
symbols use Noto artwork; all original Apple artwork remains intact. Noto's
license notices are installed alongside the report. The generated font is a
local compatibility derivative, not the byte-identical upstream release.
The build checks all 3,953 Unicode 17 RGI entries, including 396 compositions
that position two bitmap layers over one another.

Apple owns the font artwork. The converter's MIT license does not license
the font itself. The package and download are marked unfree, use local builds,
and disable substitutes. Those settings do not grant redistribution rights.
See the [upstream notice](https://github.com/samuelngs/apple-emoji-ttf/tree/484daf4e13942437e083d881cae39fbc92d837e1)
and [Apple's macOS license](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf).

This is an optional Linux font. macOS already supplies its native Apple Color
Emoji. Installing the Linux conversion there would introduce a duplicate family.
Local font installation does not require enabling downloaded color-bitmap fonts
in Firefox or Zen. That browser preference should remain disabled.

Update with `python update.py --check` to discover a new release without changing
pins. Use `python update.py --version macos-…` for an explicit release, or omit
`--version` to discover the current release. The updater records a versioned URL,
verifies GitHub's published SHA-256 and the payload's PostScript identity, and
atomically replaces source.json. Discovery may use `latest`; builds never do.
Rebuild and run the font/browser checks after updating.

## Output variants

The default retains the repaired behavior for existing users. Select an unchanged
upstream font explicitly:

```nix
pkgs.apple-color-emoji.override { repairArtwork = false; }
```

This variant is verified byte-for-byte against the pinned download. It omits
Noto additions and their repair report, and retains the three missing standalone
symbols described above. `share/doc/apple-color-emoji/variant.txt` identifies
the chosen variant. A separate Noto font is not a tested replacement for the
repair because the Apple font maps those characters to empty artwork.

The OFL permits private modification; its requirement that font derivatives be
distributed under the OFL becomes relevant when sharing the merged output.
Apple's artwork rights remain separate in both variants. Neither a local build
nor `allowUnfree` supplies a missing grant. See the
[pinned Noto license](https://github.com/googlefonts/noto-emoji/blob/v2.051/fonts/LICENSE).
Hosted CI evaluates this recipe without building either Apple-font variant
under the repository's current hosted-build policy.
