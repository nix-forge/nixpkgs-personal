# firefox-emoji

Build the package on a platform listed in `package.nix`:

```sh
nix build .#firefox-emoji
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
