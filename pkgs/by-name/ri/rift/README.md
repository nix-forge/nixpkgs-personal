# Rift

Builds Rift and its matching IPC client from the pinned Apache-2.0 release source
with Nixpkgs' Rust toolchain and offline Cargo dependencies. The native build runs
upstream's configuration, layout engine, model, config actor, input, drag,
gesture and raise-manager unit suites, and verifies both installed executables
and inspects ad-hoc signature flags and identifiers with `rcodesign`. Its
`verify` subcommand reports valid ad-hoc signatures as missing CMS; use Apple's
`codesign --verify --strict --deep` on the copied app after the sandboxed build
for full native signature-policy verification.

The full upstream suite aborts in the sandbox on macOS 26:
reactor fixtures call live SkyLight window queries from synthetic space snapshots
(`forwarded_space_state`), reaching `SLSWindowManagementFallbackBridge`. These
session-dependent suites and AppKit integration tests need separate native
runtime verification; the package does not patch their production behavior or
claim they passed. The explicit headless suite list is in `package.nix`.

The internal `unwrapped` derivation compiles and tests both binaries independently
of the application wrapper; bundle-only changes reuse that checked output.

The package installs `Applications/Rift.app`, `bin/rift` and `bin/rift-cli`, plus
the upstream license and example configuration. A generated property list uses
the upstream application identifier and compiler deployment minimum. The bundle
is locally signed; it does not claim Developer ID signing or notarization.

Use `homeManagerModules.rift` from this collection for a stable copied app,
declarative TOML, and one launchd-managed instance. Grant macOS Accessibility to
the copied app when prompted. Overview and previews are disabled by the module's
defaults; normal window management does not require Screen Recording.

Updates are manual for now: update `source.nix` to a matching release commit,
verify the source hash, refresh the Cargo vendor hash, run the package and module
checks on macOS, and verify the copied app's permission identity and live config
reload. Automatic updates are intentionally omitted until that migration path
has native upgrade evidence. Changing a release must retain both binaries from
the same source build.
