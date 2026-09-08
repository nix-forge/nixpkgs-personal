# anthropic-skills

Build the package on a platform listed in `package.nix`:

```sh
nix build .#anthropic-skills
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

## Updates

Run `python3 pkgs/by-name/an/anthropic-skills/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction requires a separate native smoke test.
