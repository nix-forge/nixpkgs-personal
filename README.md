# nixpkgs-personal

Personal Nix packages published as a small, standalone flake. It has no
dependency on the NixOS, nix-darwin, or Home Manager inputs from my personal
configuration.

Browse the [complete package catalog](docs/catalog.md) for build commands,
platforms, source recipes, upstream links and licenses. Start with one package;
you do not need the workstation configuration to use this collection.

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

Direct `packages` and `legacyPackages` outputs enable `allowUnfree` internally.
The caller's NixOS or Home Manager unfree setting does not configure those
separate imports. To enforce a selective policy, use the overlay or ordinary
`default.nix` import with your configured `pkgs`:

```nix
pkgs = import nixpkgs {
  inherit system;
  overlays = [ nixpkgs-personal.overlays.default ];
  config.allowUnfreePredicate = package:
    builtins.elem (nixpkgs.lib.getName package) [
      "openai-skills"
      "ttf-ms-win11-auto"
    ];
};
```

Keep `allowUnfree = false`, its default, when using a selective predicate.
The Anthropic catalog defaults to reviewed free examples; restricted skills
are separately selectable. The full OpenAI catalog still requires unfree
consent and also offers a free selection. The [metadata research](docs/package-metadata-research.md) explains
license classification, source provenance and build settings. The
[metadata audit](docs/package-audit.md#metadata-and-unfree-review-2026-09-08)
records the reviewed package classifications.

| Platform | Package coverage |
| --- | --- |
| `x86_64-linux` | Fonts, skills, Linux desktop packages, cursors, Spotify and CEF helper |
| `aarch64-linux` | Fonts, skills, Codex Desktop, Noctalia and cursors |
| `aarch64-darwin` | Fonts, skills and macOS applications |

Use `nix eval --json .#packages --apply 'builtins.mapAttrs (_: builtins.attrNames)'`
for the exact platform inventory. Linux-only packages are not exported on macOS.

`x86_64-darwin` is intentionally unsupported because nixpkgs unstable has
dropped that platform. Several packages are proprietary or subject to upstream
terms. Recipes fetch those vendor payloads when users build them; this repository
does not publish those payloads or provide a public binary cache. It does include
source code for bundled utilities and a vendored expression, with their retained
notices. The root MIT license applies to the repository's original code, not to
everything downloaded by a recipe. See the [licensing policy](docs/package-licensing.md)
for hosted-build exclusions and unresolved permission questions.

## Development and updates

The `pre-commit` flake check runs portable hooks inside the Nix sandbox. Xcode
formatting, SourceKit linting and native Swift quality suites remain in local
Git hooks and required macOS CI jobs. Their definitions are grouped in
`flake/dev/git-hooks.nix`, so adding a host-dependent hook does not require a
second exclusion list. Portable hooks use the same commands in both environments.

CI builds `lintChecks` once in the required Linux lint job. Native jobs discover
`ciChecks`, which excludes that lint owner's inventory. The ordinary `checks`
output retains all checks for local validation. New native checks enter CI by
default; additions to the lint group run in its existing required job.

The lint group is reserved for portable tooling. Platform-dependent tests belong
in native checks or a required native job, so moving lint does not hide them.

Run `just check`, `just lint`, and `just update-packages`. Update scripts only
change pinned source metadata and are checked by CI before automated merge. New
packages follow the nixpkgs-style `pkgs/by-name/<prefix>/<name>` layout and must
declare accurate metadata, platform support, tests where feasible, and an
updater when upstream can be safely discovered.

All public packages have their own directory and can be instantiated with
upstream Nixpkgs using `pkgs.callPackage ./package.nix { }`. Package build files,
helpers, tests, and updaters stay within that directory. Upstream Nixpkgs
libraries and tools remain normal dependencies.

Package small installed Bash commands with `writeShellApplication` and declare
their command dependencies in `runtimeInputs`. Use `writers.writePython3Bin`
for one executable Python file and `buildPythonApplication` for a distributable
Python application. Patch unpacked upstream source with
`substituteInPlace --replace-fail`. Use `replaceVars` or `replaceVarsWith` for
complete `@name@` file templates, and keep `builtins.replaceStrings` for small
evaluation-time string transformations.

The overlay resolves direct and nested `callPackage` arguments against its
incoming upstream scope. It does not inject this collection's outputs into
another personal package. Explicit `.override` remains available.

Run `just test` for package independence and Python tests. CI also evaluates all
three systems and builds eligible affected packages on matching runners. The independence
check copies each package directory into the store and rejects dependencies on
any public personal package. Updater import checks run outside the checkout.

See the [package standard](docs/package-standard.md),
[research and language decisions](docs/package-design-research.md), and
[package audit](docs/package-audit.md).

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
Linux conversion with its own source verification and installer. It is an optional
family and installs no Fontconfig overrides. See its
[source and compatibility notes](pkgs/by-name/ap/apple-color-emoji/README.md).
Individual assets are available through `apple-fonts.assets`. Eight separate
`apple-sf-*` and `apple-new-york` packages provide Apple's developer fonts.
The developer fonts each have an independent package directory and source manifest.
These packages are unfree and opt-in; they do not change font defaults.

The package includes a catalog/DMG updater, verified payload inventories, and
an archive exporter/importer for fonts from a known Mac build. See the
[Apple font package guide](pkgs/by-name/ap/apple-fonts/README.md) for usage,
source retention limits, and licensing details.

## NUR preparation

The root `default.nix` supports NUR and non-flake consumers with caller-supplied
Nixpkgs. Registration is pending. See [NUR usage, compatibility and submission](docs/nur.md).
