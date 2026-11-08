# LightCraft

Source build of [LightCraft 0.8.0](https://github.com/storytold/lightcraft/releases/tag/v0.8.0) at `16dbb90499d3c63a6582fcbba1b2550a6e2da032`.
Installs `lightcraft` and `lightcraft-cli`, retaining the default automation/plugin capabilities.
The pinned craft-fonts collection is embedded with required-input checking for multilingual text.

Linux includes X11/Wayland and Vulkan/OpenGL loader paths, desktop entries, icons and available MIME definitions. macOS includes a native app bundle with upstream document declarations and an ad-hoc signature. The CLI remains independently invocable. Browser/WASM targets and developer xtask are not desktop deliverables.

The build runs native workspace library tests and installed CLI/desktop checks. Separate package checks exercise document exports and GUI startup. Tests needing external corpora, optional models, services or physical devices need separate upstream integration runs. See [the packaging research and validation record](../../../../docs/artcraft-packaging-research.md) for completed checks and platform limits.

The public flake exports x86_64-linux, aarch64-linux and aarch64-darwin. For Intel macOS, call this independent recipe with `pkgs.callPackage ./package.nix { }` from a Nixpkgs 26.05 instance providing Rust 1.95 or newer. Nixpkgs 26.11 dropped Intel Darwin support, so the current public flake and its overlay do not expose that system.

SAM3 masking weights are not redistributed. Upstream supplies no default mirror; configure a model mirror/token or install the weights manually using the application’s model settings and applicable upstream terms.

Updates are manual: inspect an upstream release/commit and its manifests, asset terms and packaging templates; update `source.nix` and its release metadata, review and refresh the checked-in Cargo locks and font pin, recompute immutable source and Git dependency hashes, then rebuild with strict sandboxing. These projects are early alpha with rapidly changing interfaces, so unattended updates are not enabled.

Non-NixOS graphics can require [nixGL](https://github.com/nix-community/nixGL) using the same Nixpkgs pin as this package.

On macOS a local Candle patch returns an error when no requested Metal device
is visible, allowing upstream CPU inference fallback. The missing/corrupt-model
library regressions remain enabled. Metal acceleration remains available when
a device is present.

The original profile-hover fixture and its upstream waits remain enabled on ARM
Linux. Its former ten-minute allowance was removed after focused selected-source
tests passed under QEMU 11.1.2. All non-ignored loupe tests also pass in the full
serialized QEMU UI run below; a concurrent sandbox control still fails. Ordinary
cross builds do not run target unit tests by default. See the
[patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md)
for the exact test results and their limits.

For explicit QEMU test jobs, retain the runner's normal CPU affinity and budget
Rayon independently from compiler jobs. The measured heavy loupe cohort passes
inside the strict Nix sandbox with `RAYON_NUM_THREADS=8` and libtest
`--test-threads=1`; the concurrent sandbox control fails. Apply this policy to
the explicit emulated validation job, preserving native ARM concurrency. The
full-suite result below extends that focused evidence; it does not establish
sandboxed application compilation.

The selected release provides pure Rust HEIC/HEIF decoding. Both GUI and CLI
build with their `heif` features, alongside default JPEG XL/AVIF and denoise
features. Native checks additionally run the upstream synthetic codec integration
suite for colour, orientation, thumbnails, bit depth and hostile inputs. This
suite remains offline and does not need an external photo corpus or a GPU.
Linux advertises `image/heic` and `image/heif` desktop associations. Refreshed
source and decoder test results are pending the current build matrix.

See the [patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md) for this source update. Earlier completed build receipts apply only to their recorded revisions.

## Explicit QEMU UI checks

`lightcraft.mkEmulatedUiTest` creates a Linux execution check from a separately
compiled ARM UI-library test executable. It requires an explicit QEMU package
at version 11.1.2 or newer, the ARM runtime libraries and any runtime fixture
store paths. It does not build the application or alter native ARM checks.

```nix
lightcraft.mkEmulatedUiTest {
  inherit pkgs qemu;
  testExecutable = "${uiTestArtifact}/bin/lightcraft-ui-tests";
  runtimeLibraries = [ armGlibc armGccLib ];
  testFixtures = [ uiTestSource ];
  expectedTestCount = 846;
}
```

Here `pkgs` is the Linux build-host package set. The other values are caller
inputs: a compatible QEMU, the UI test artifact, its target runtime libraries and
its immutable source fixtures. Compile the UI crate with a store-based
`CARGO_MANIFEST_DIR`; two catalog tests read locale files relative to that path.
Declare those fixtures rather than binding a developer checkout into the
sandbox. The raw Nixpkgs pin may provide an older QEMU, so this check deliberately
does not select an emulator implicitly.

The check retains normal CPU affinity, uses eight Rayon workers and one libtest
thread, disables GPU access through the supported flag, and isolates HOME/XDG
state. It discovers the entire executable and upstream ignored tests before
running without filters or added skips. Standard libtest capture keeps failure
output; verbose profiling is disabled. The default process deadline is two
hours and can be set with `timeoutSeconds`. Execution failures, incomplete
summaries and count mismatches fail the derivation.

Successful outputs contain discovery, emulator version, suite logs and a JSON
receipt with exact counts, ignored names and executable identity. Use Nix's
`--keep-failed` when investigating failures; the check copies available logs to
its output, prints its receipt to the build log and retains a nonzero status.
Sandboxed execution of a supplied artifact does not prove its compilation was
sandboxed. See the [implementation](scripts/emulated-ui-test.nix) and
[validation record](../../../../docs/research/artcraft-patch-retirement-research.md)
for measured scope and remaining limits.

The selected 0.8.0 UI executable accounted for all 846 tests under QEMU 11.1.2 with
`sandbox = true`: **842 passed, one failed, three upstream ignored, zero
filtered**, in 1839.74 seconds. All non-ignored loupe tests passed. The contact-sheet
menu/dialog/background-export test failed its original 20-second completion
assertion. Upstream already [reworked that fixture after the selected release](https://github.com/storytold/lightcraft/pull/1406);
the recorded failure alone does not distinguish slow work from a masked export
error. The check correctly failed and retained its complete result.

A separate same-artifact sandbox control passed the original contact-sheet test
alone in 13.72 seconds. This supports a full-suite context/timing problem, while
leaving the complete failed result above intact. No timeout or source patch was
added to obtain that control result.

The existing upstream fixture repair has since been verified experimentally.
With only its test hunk applied, the full QEMU sandbox UI suite passed:
**843 passed, zero failed, three upstream ignored, zero filtered**, in 1842.62
seconds. A matched 32-test sequence changed from 31 passed/one failed to all
32 passed, preserving the 20-second guard and PDF assertions. The package recipe
has not adopted this experimental test hunk; native ARM behavior is unchanged.
See the [verification record](../../../../docs/research/artcraft-patch-retirement-research.md#verification-of-the-upstream-contact-sheet-fixture-repair-2026-10-16).
