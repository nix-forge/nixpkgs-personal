# nixpkgs-personal

Personal Nix packages published as a small, standalone flake. It has no
dependency on the NixOS, nix-darwin, or Home Manager inputs from my personal
configuration.

## Use

Add the flake and make its `nixpkgs` input follow yours:

```nix
inputs.nixpkgs-personal = {
  url = "github:nix-forge/nixpkgs-personal";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Packages are available as `inputs.nixpkgs-personal.packages.${system}`. To add
them to `pkgs`, use `inputs.nixpkgs-personal.overlays.default`.

| Platform                        | Supported outputs                 |
| ------------------------------- | --------------------------------- |
| `x86_64-linux`, `aarch64-linux` | ChatGPT/Codex Desktop, agent skills, cursors, and Windows 11 fonts |
| `aarch64-darwin`                | All packages                      |

`x86_64-darwin` is intentionally unsupported because nixpkgs unstable has
dropped that platform. Several packages are proprietary or subject to upstream
terms; this repository packages them but does not redistribute their sources or
provide a public binary cache.

## Development and updates

Run `just check`, `just lint`, and `just update-packages`. Update scripts only
change pinned source metadata and are checked by CI before automated merge. New
packages follow the nixpkgs-style `pkgs/by-name/<prefix>/<name>` layout and must
declare accurate metadata, platform support, tests where feasible, and an
updater when upstream can be safely discovered.

The WireGuard roaming controller runs rustfmt, Rust compiler checks, strict
Clippy, tests, rustdoc, cargo-machete, and cargo-deny during its Nix build. The
development shell supplies the same Rust tools. CI also checks current RustSec
advisories and scans the Rust source with CodeQL.

## Dark application icons

`noctalia-dark-app-icons` is available on both Linux platforms and through the
default overlay. It adds dark ChatGPT, Zen and VS Code artwork, with upstream
Papirus-Dark as the fallback. It includes source attribution, license notices,
an icon cache, desktop-entry aliases and rendering checks. Appearance switching
belongs to the desktop configuration. See the
[package notes](pkgs/by-name/no/noctalia-dark-app-icons/README.md) for coverage
and the reviewed source update policy.

```sh
nix build .#noctalia-dark-app-icons
```

`noctalia-personal` builds the pinned upstream shell with configurable symbolic
bar icons and exact tray icon lookup. Symbolic artwork follows the bar's
foreground color; dock artwork continues to use the icon theme. See its
[package notes](pkgs/by-name/no/noctalia-personal/README.md) for the patch scope
and source update checks.

## Optional emoji fonts

`firefox-emoji` 1.7.9 and `emojione-legacy` 2.2.7 are available on all three
flake platforms and through the default overlay. Firefox Emoji uses COLR/CPAL;
EmojiOne uses SVG OpenType, so color rendering depends on application support.
Both preserve the original family names and font bytes, ship attribution and
upstream license notices under `share/doc`, and install no Fontconfig policy.
They are optional historical designs, not replacements for a current default
emoji font such as Noto Color Emoji.

Nixpkgs has no Firefox Emoji package at the reviewed pin. Its former `emojione`
package was removed because upstream was archived. The explicit
`emojione-legacy` name avoids overriding that removed alias or confusing this
CC-BY-4.0/MIT release with later EmojiOne/JoyPixels licensing.

Build and run the included font checks with:

```sh
nix build .#firefox-emoji .#emojione-legacy
```

The checks verify untouched source bytes, Fontconfig family identity, the 14
EmojiTest face glyphs, and their COLR/CPAL or SVG color data. Both packages are
also exposed as flake checks. Their `source.nix` files pin immutable upstream
revisions and hashes for the fonts and licenses. These compatibility releases
are intentionally excluded from automatic updates. Changing them requires
reviewing the upstream license, family identity, color rendering, ordinary
numeric text, and default emoji fallback again.

`mutant-standard-emoji` builds the official 2024.06 codepoint SVG archive with
upstream nanoemoji as a COLRv1 font. It keeps the family name
`Mutant Standard Emoji` and installs no default-font policy. All 7,829 supplied
encodings are checked with HarfBuzz against the final color table. Artwork is
by Caius Nocturne under CC BY-NC-SA 4.0; attribution and upstream credit files
are included. See the [package notes](pkgs/by-name/mu/mutant-standard-emoji/README.md)
for renderer requirements and coverage limits.

```sh
nix build .#mutant-standard-emoji
```

## Apple fonts

`apple-fonts` provides a pinned selection of macOS Font8 catalog assets.
The separate `apple-color-emoji` package provides a versioned, SHA-256-pinned
Linux conversion with the same verified manifest installer. It is an optional
family and installs no Fontconfig overrides. See its
[source and compatibility notes](pkgs/by-name/ap/apple-color-emoji/README.md).
Individual assets are available through `apple-fonts.assets`. Eight separate
`apple-sf-*` and `apple-new-york` packages provide Apple's developer fonts.
These packages are unfree and opt-in; they do not change font defaults.

The package includes a catalog/DMG updater, verified payload inventories, and
an archive exporter/importer for fonts from a known Mac build. See the
[Apple font package guide](pkgs/by-name/ap/apple-fonts/README.md) for usage,
source retention limits, and licensing details.
