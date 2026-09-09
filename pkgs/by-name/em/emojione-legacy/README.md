# emojione-legacy

Build the package on a platform listed in `package.nix`:

```sh
nix build .#emojione-legacy
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

## Updates

This package has no automatic updater. Review upstream changes and licenses
when updating its source pin or the Nixpkgs input used by its override.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction requires a separate native smoke test.

## Adobe font provenance

The pinned [font README](https://github.com/joypixels/emojione/blob/0aad7f9f7969f0187e4f50d12fdc113541a34ac3/assets/fonts/README.md)
credits a cooperative effort with Adobe Systems. The corresponding
[Adobe font and full MIT notice](https://github.com/adobe-fonts/emojione-color/tree/835b4ef8384f55ecf9abf7ecc943a3980884690b)
identify Copyright (c) 2016 Adobe Systems Incorporated.

The reviewed Adobe OTF and this package's pinned OTF have identical CFF, SVG,
cmap, GSUB, name, metrics, and other substantive font tables. Adobe's copy adds
DSIG; only the corresponding head checksum adjustment differs otherwise.
The output retains the original font bytes, Adobe's complete MIT notice,
EmojiOne's artwork terms, and the embedded Adobe/EmojiOne credits. Current
JoyPixels terms are not substituted for this historical release's license.
