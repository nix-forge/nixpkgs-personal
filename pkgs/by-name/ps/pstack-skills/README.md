# pstack-skills

Build the package on a platform listed in `package.nix`:

```sh
nix build .#pstack-skills
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

## Updates

Run `python3 pkgs/by-name/ps/pstack-skills/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself.

Git is required for discovery. The updater fetches public `main` commit metadata
without credentials because Cursor's organization IP allow list rejects
authenticated API requests from hosted runners. This also avoids the shared
runner's anonymous API quota. The metadata fetch is shallow and excludes blobs;
the source archive is still prefetched separately and recorded with its SRI hash.
The version date uses the commit's authored date in UTC.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction requires a separate native smoke test.
