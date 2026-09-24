# ocr-capture

This directory contains the Nix package recipe for
[ocr-capture](https://github.com/IanHollow/ocr-capture). The source code, user guide,
tests, and security policy live in that repository.

Build the pinned source revision with:

```sh
nix build github:nix-forge/nixpkgs-personal#ocr-capture
```

The recipe fetches a fixed GitHub revision and verifies its Nix content hash.
Review upstream changes and update the revision and hash together.
