# steam-cef-scale-override

This directory contains the Nix package recipe for
[steam-cef-scale-override](https://github.com/IanHollow/steam-cef-scale-override). The source code, user guide,
tests, and security policy live in that repository.

Build the pinned source revision with:

```sh
nix build github:nix-forge/nixpkgs-personal#steam-cef-scale-override
```

The recipe fetches a fixed GitHub revision and verifies its Nix content hash.
Review upstream changes and update the revision and hash together.
