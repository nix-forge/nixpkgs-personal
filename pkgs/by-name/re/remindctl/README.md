# remindctl

Build the package on a platform listed in `package.nix`:

```sh
nix build .#remindctl
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

The release ZIP contains only the signed executable. Packaging preserves its
bytes and installs the matching release's MIT notice under `share/doc/remindctl`.
The notice hash in `package.nix` needs manual review if an update changes it.

## Updates

Run `python3 pkgs/by-name/re/remindctl/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself. Archive layout, arm64
Mach-O support and source hashes are checked without executing the download.
The native Nix install check verifies the binary reports the pinned version.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction requires a separate native smoke test.
