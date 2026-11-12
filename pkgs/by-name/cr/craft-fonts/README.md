# craft-fonts

Installs the pinned upstream multilingual font collection with its manifest,
family licenses and attribution. Validates each font's upstream checksum and
license before installation. This is font data; it does not install the optional
Rust manifest-reading library. Application recipes embed this source separately
so each package remains independently copyable.

Updates are manual: review the upstream manifest and font provenance, refresh
`source.nix`, run the manifest validation and refresh consuming applications' font pins, then rebuild those applications
with strict sandboxing.

The standard Nixpkgs `installFonts` hook installs fontconfig-facing files under `share/fonts/truetype` and `share/fonts/opentype`. The original `fonts/manifest.txt`, relative font paths and notices remain available for build-input consumers. Installing this package does not configure a desktop session to use it.
