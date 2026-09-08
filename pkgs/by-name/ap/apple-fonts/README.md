# Apple font packages

These packages fetch fonts directly from Apple and preserve their bytes. They
are opt-in. Adding them to the personal package collection does not install
fonts or change Fontconfig aliases, fallback, or the native macOS system fonts.

`apple-fonts` contains the selected macOS Font8 catalog assets. The updater
selects assets advertised for macOS installation, download, or document
autoactivation. It retains complete collections, including internal faces in
the same file. Installing the aggregate makes these files available together;
it does not reproduce Apple's on-demand activation policy. Prefer individual
assets when you only need a family.

The updater resolves duplicate asset revisions by their numeric mastered
version. A replacement must contain every face of the superseded asset.
Partial overlaps fail for review. This collection is a catalog snapshot, not
all fonts from a macOS release. It omits OS-only fonts such as Apple Color Emoji
and does not combine the historical Font7 catalog with Font8.

The separate `apple-color-emoji` Linux package uses a versioned third-party
conversion release. It reuses this installer's `fromSource { manifestFile = ...; }`
interface for pinned downloads, including individual TTF/TTC/OTF/OTC/dfont files.
It is outside the Apple-hosted catalog aggregate; see
[its source and compatibility notes](../apple-color-emoji/README.md).

From this package repository:

```sh
nix build .#apple-fonts
nix build .#apple-fonts.assets.apple-asset-albayan
nix build .#apple-sf-mono
```

The eight independent developer packages are `apple-sf-pro`, `apple-sf-compact`,
`apple-sf-mono`, `apple-new-york`, `apple-sf-arabic`, `apple-sf-armenian`,
`apple-sf-georgian`, and `apple-sf-hebrew`. They are outside the catalog aggregate.
Their original DMG URLs are mutable. A pinned hash detects replacement but
cannot make Apple retain old downloads.

With the personal overlay enabled, use an explicit package selection:

```nix
fonts.packages = [
  pkgs.apple-fonts.assets.apple-asset-albayan
];
```

For Home Manager, add the chosen derivation to `home.packages`. On Darwin,
Home Manager and nix-darwin copy fonts into their managed native font
locations. File extensions are normalized to lowercase and `.otc` becomes
`.ttc` so nix-darwin's extension filter can find the collection. This only
changes filenames; it does not convert font data. Dfont files are installed
explicitly. Legacy resource-fork suitcase fonts require separate handling.

## Update sources

Run the updater from a shell containing Python 3.12 or newer, Fontconfig, and
7-Zip with its `7zz` executable. The dedicated development shell provides them:

```sh
nix develop .#apple-fonts -c python pkgs/by-name/ap/apple-fonts/update.py --check
nix develop .#apple-fonts -c python pkgs/by-name/ap/apple-fonts/update.py
```

The repository dispatcher also discovers this updater:

```sh
nix develop .#apple-fonts -c python scripts/update-packages.py --package apple-fonts -- --dry-run
```

`--check` reports a change with exit status 1, and `--dry-run` prints the diff
without writing. Both can download new sources into the local cache.
`--cache-dir` selects that cache. Catalog assets must match Apple's advertised
size and SHA-1, and every archive gets an independent SHA256 pin. Developer
DMGs are checked again on every update. Normal package builds never query the
live catalog.

`sources.json` records the catalog digest, collection snapshot date,
per-source URL/build/hash, expected payload paths, file hashes, and named
PostScript faces. The updater parses every selected source before atomically
replacing the manifest. Each build checks its complete payload inventory,
then verifies installed bytes and face names. Original license and notice
files are copied into `share/doc`. No installer scripts execute.

The first update downloads approximately 1.4 GB. Subsequent checks reuse
unchanged catalog archives. Retain the source cache if you need to rebuild a
developer release after Apple replaces its public DMG. Do not publish the
cache or package outputs without redistribution rights.

The cache retains content-addressed files named `<sha256-hex>.dmg` or `.zip`
alongside its URL lookup entries. To restore an old source into the store, use
`nix store prefetch-file --name <package>-<version>.dmg file:///absolute/cache/path.dmg`.
Use the package name and version from that release's manifest. Later updater
runs keep these older files.

## Import OS-only fonts

Run the exporter on the Mac containing the desired font versions. Give it
explicit directories and record the macOS version and build. Include applicable
license notices with repeatable `--notice` arguments. A native export is needed
because full current macOS installer extraction has not been validated.

```sh
nix develop .#apple-fonts -c python pkgs/by-name/ap/apple-fonts/export.py \
  /System/Library/Fonts \
  --version 26.0-25A354 \
  --archive /tmp/macos-fonts-26.0-25A354.tar \
  --manifest /tmp/macos-fonts-26.0-25A354.json
```

Replace the example version with the Mac's actual `sw_vers` values. The exporter
creates a deterministic archive and manifest, rejects duplicate PostScript
names, and refuses to overwrite existing outputs. It preserves regular-file
TTF/TTC/OTF/OTC/dfont data. It does not collect every on-demand font, application
bundle, or old resource-fork format automatically. Avoid including managed
Nix font directories again.

Keep the JSON manifest in your configuration and supply the archive privately:

```nix
fonts.packages = [
  (pkgs.apple-fonts.fromArchive {
    manifestFile = ./macos-fonts-26.0-25A354.json;
  })
];
```

The resulting `requireFile` message describes how to add the named archive to
the Nix store with `nix-store --add-fixed sha256`. Alternatively pass `src` as
an explicit Nix path or fixed-output fetcher. Even with an overridden source,
the build checks the archived font inventory. The archive contains font data;
the JSON contains metadata, paths, and hashes.

## Usage limits and validation

Apple fonts have different licenses. The developer-font agreements restrict
use to specified Apple-platform UI mock-ups and impose additional conditions.
A local import does not establish general Linux-use or redistribution rights.
Packages and fetched sources are marked unfree, prefer local builds, and
disable substitutes. These Nix settings do not grant rights or prevent a
separately configured cache-upload hook from publishing outputs.

The package recipe retains available upstream notices and this explanation.
Catalog ZIPs that do not ship a standalone agreement remain subject to the
applicable Apple and font-owner terms. Consult the [Apple font agreements](https://developer.apple.com/fonts/)
and [macOS license](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf).

Font parsing is checked on Linux. Native Core Text rendering, application
shaping, and color-font support remain separate checks. No package promises
that Apple Color Emoji or every historical font renders in every application.
