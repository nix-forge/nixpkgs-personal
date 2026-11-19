# Rift

Builds Rift 0.8.3 and its matching IPC client from the pinned Apache-2.0 release
source with Nixpkgs' Rust toolchain and offline Cargo dependencies. The native build runs
upstream's configuration, layout engine, model, config actor, input, drag,
gesture and raise-manager unit suites. The install phase signs the app and IPC
client with `rcodesign`; the former package-owned executable and signature
install checks are retired. `rcodesign verify` reports valid ad-hoc signatures as
missing CMS; use Apple's
`codesign --verify --strict --deep` on the copied app after the sandboxed build
for full native signature-policy verification.

Earlier native validation found that 0.7.2 reactor fixtures queried live
SkyLight state from synthetic space snapshots and aborted without WindowServer
in the macOS 26 sandbox. The package retains its explicit headless suite list in
`package.nix` for 0.8.3. Although that release includes upstream work on headless
fixtures, the unfiltered suite and AppKit integration still need separate native
verification; the retained filter does not establish that they pass.

Upstream 0.8.3 forwards key-free `KeyboardInput` intent and clears the lifecycle
suppression guard after keyboard activity. The workstation's guarded consumer
overlay now adds only a repeat-event exclusion, preserving the policy that held
keys and Rift's synthetic events do not count as fresh user intent. This reusable
recipe does not carry that consumer patch. Validate native shortcuts, wake and
unlock behavior on the copied app when changing either source or integration.

The internal `unwrapped` derivation compiles both binaries and runs the headless
library suites independently of the application wrapper; bundle-only changes
reuse that output.

The package installs `Applications/Rift.app`, `bin/rift` and `bin/rift-cli`, plus
the upstream license and example configuration. A generated property list uses
the upstream application identifier and compiler deployment minimum. The bundle
is locally signed; it does not claim Developer ID signing or notarization.

Use `homeManagerModules.rift` from this collection for a stable copied app,
declarative TOML, and one launchd-managed instance. Grant macOS Accessibility to
the copied app when prompted. Overview and previews are disabled by the module's
defaults; normal window management does not require Screen Recording.

Updates are manual for now: update `source.nix` to a matching release commit,
verify the source hash, refresh the Cargo vendor hash, run the retained upstream
suites on macOS, and verify the copied app's permission identity and live config
reload. Automatic updates are intentionally omitted until that migration path
has native upgrade evidence. Changing a release must retain both binaries from
the same source build.
