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
pre-seeded Electron download cache. Staging preserves the installed pnpm
peer contexts and dependency links, with lock metadata for Electron Builder's
production dependency collector. See `linux.nix` for the build steps.

Only `x86_64-linux` is offered because that is the only Linux architecture
upstream releases and tests. The recipe follows the same Electron structure
as `openai-codex-desktop` (`package.nix` dispatcher with per-platform
`darwin.nix`/`linux.nix` backends).

## Updates

Run `python3 pkgs/by-name/t3/t3-code/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself. Candidate pins are
written to a temporary copy, so previews and failed updates leave the package
untouched.

Pass `--nixpkgs github:NixOS/nixpkgs/<revision>` to select the upstream Nixpkgs
revision used to rebuild dependency mirrors. The default is the `nixpkgs` flake
registry entry. Use the same revision as the consuming package set, since
fetcher changes can affect dependency hashes. No surrounding flake is needed.
The updater always instantiates the local Linux recipe as `x86_64-linux`,
including on Darwin; rebuilding its mirrors requires a configured Linux builder
when the local host cannot build them.

`--check` only compares release metadata and stays cheap. A real update
re-downloads every artifact and rebuilds the offline pnpm/cargo mirrors to
refresh their hashes, which downloads the full dependency closures once per
revision. The Electron runtime version is read from
`apps/desktop/package.json` inside the tagged source so vendored native
prebuilds keep their ABI.

The package expression records platform support, licensing, and build checks.
The Linux install check loads packaged native terminal, keyring, and MessagePack
modules and checks the bundled server's version. Darwin build checks preserve
the signed bundle and verify its entrypoints; native runtime checks run outside
the build sandbox.

Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction and authenticated provider sessions
require separate native smoke tests. The package tests cover copied-directory
updates, failed-update cleanup, dependency cycles, peer contexts, and pnpm's
staged dependency enumeration.
