# t3-code

Build the package on a platform listed in `package.nix`:

```sh
nix build .#t3-code
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

macOS (`aarch64-darwin`) installs the official signed and notarized
application bundle. Linux (`x86_64-linux`) compiles the application from the
tagged upstream source with the workspace's own artifact script and wraps the
result as a native package: no AppImage runtime or FUSE involved. The Linux
build stays fully offline through the pinned pnpm/cargo mirrors and a
pre-seeded Electron download cache; see `linux.nix` for the exact mechanism.

Only `x86_64-linux` is offered because that is the only Linux architecture
upstream releases and tests. The recipe follows the same Electron structure
as `openai-codex-desktop` (`package.nix` dispatcher with per-platform
`darwin.nix`/`linux.nix` backends).

## Updates

Run `python3 pkgs/by-name/t3/t3-code/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself.

`--check` only compares release metadata and stays cheap. A real update
re-downloads every artifact and rebuilds the offline pnpm/cargo mirrors to
refresh their hashes, which downloads the full dependency closures once per
revision. The Electron runtime version is read from
`apps/desktop/package.json` inside the tagged source so vendored native
prebuilds keep their ABI. Mirror refreshes require an `x86_64-linux` builder,
including when the updater runs on macOS. Repository updates use the locked
Nixpkgs input; a copied directory uses the caller's `nixpkgs` flake registry
entry. On the desktop host, run mirror refreshes through `workstation-task`.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction requires a separate native smoke test.
