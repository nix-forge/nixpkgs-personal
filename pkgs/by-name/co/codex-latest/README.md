# codex-latest

The upstream Nixpkgs source-built Codex CLI recipe with independently maintained
stable source and dependency pins for x86-64 Linux, ARM64 Linux and Apple Silicon
macOS. The recipe retains upstream's patches, runtime layout, shell completions,
voice support and companion `codex-code-mode-host` build. V8's upstream static
library is a pinned binary dependency; the CLI itself is compiled from source.

```sh
nix build .#codex-latest
python3 pkgs/by-name/co/codex-latest/update.py --dry-run
```

The updater resolves GitHub's latest stable release once, resolves its tag to a
full commit, and reads that commit's Cargo.lock with `tomllib`. Drafts,
prereleases, malformed releases, downgrades and changed identities for an existing
version are rejected. Exactly one registry V8 dependency must exist. Both the
V8 archive and generated Rust binding are refreshed for every supported target.

A new release also refreshes the recursive source hash, build commit and Cargo
vendor hash. The Cargo fetcher is evaluated against `NIXPKGS_UPDATE_SOURCE` from
the native updater, or `NIX_PATH` for a direct Python call. It first obtains the
fixed-output mismatch from a temporary candidate, then builds the dependency
fetcher with the resolved hash to verify it. An unrelated build failure cannot
be interpreted as a checksum. All related pins publish together in one
`source.nix` transaction after preparation succeeds. Ordinary publication errors
roll back; power loss and SIGKILL are outside that guarantee.

`--dry-run` performs changed downloads and dependency preparation without editing
pins. It can be expensive on a new release. On the desktop host, run it through
`workstation-task`. Timeouts and upstream recipe incompatibilities leave source
pins unchanged. Updates do not automatically change the underlying Nixpkgs Rust
toolchain or patch set; a release that needs recipe changes fails for review.

The packaged updater declares Python, Nix, nixfmt and certificate dependencies.
It accepts `--package-dir` or `UPDATE_NIX_PACKAGE_DIR` for editable standalone
copies. It never commits or pushes. The existing daily package workflow discovers
it, opens its own PR and requires CI before merge. Configuration deployment is a
separate step.

This package is independent of the desktop application. Pass it to
`chatgpt-latest.override { codex = pkgs.codex-latest; }` in the consumer when
Linux desktop and terminal tasks should use the same CLI.

Sources: [Nixpkgs recipe](https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/by-name/co/codex),
[Codex releases](https://github.com/openai/codex/releases),
[V8 release artifacts](https://github.com/denoland/rusty_v8/releases).
