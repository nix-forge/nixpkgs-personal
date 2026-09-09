# linearmouse

Build the package on a platform listed in `package.nix`:

```sh
nix build .#linearmouse
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

## Updates

Run `python3 pkgs/by-name/li/linearmouse/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself.

`source.nix` pins both the DMG and the configuration schema from the same release
with content hashes. The updater fetches both before replacing the metadata;
if the release schema is missing, the existing pins remain unchanged.

The package exposes `configurationSchema` and `configurationSchemaVersion` for
configuration modules to validate generated JSON without building the application.
The schema currently bundles all references. Consumers should require a bundled
schema or pin every referenced file before validating offline. Validation does
not verify device availability or macOS permissions.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction requires a separate native smoke test.
