# apple-sf-hebrew

Apple's developer font distribution, pinned by URL, SHA-256, and a complete
font inventory in `source.json`. This directory builds independently with
upstream Nixpkgs and installs no default font selection policy.

```sh
nix build .#apple-sf-hebrew
```

The build verifies the extracted and installed font hashes and PostScript face
names. It preserves upstream notices and installs its manifest under `share/doc`.
Apple's font license applies; this is an opt-in unfree package with substitution
disabled. A content hash does not guarantee Apple retains a download forever.

Updates require reviewing this package's `source.json` against the versioned
Apple download and rebuilding to check every recorded font. There is no
unattended updater. Python handles archive inspection; Nix declares the build.
