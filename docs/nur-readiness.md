# NUR readiness

Prepared on 2026-09-07 (America/Los_Angeles). Registration is pending.

## Implemented

- A root `default.nix` forwards caller-supplied `pkgs` to the package registry.
- CI runs NUR's restricted evaluator and a separate three-platform compatibility
  check against locked Nixpkgs and current `nixos-unstable`.
- Supported packages must declare a license; unfree packages must explicitly
  declare source provenance.
- Precompiled Apple and historical emoji font inputs now declare
  `binaryBytecode` provenance. Mutant Standard's font compiled from source declares
  `fromSource`. Existing upstream licenses and redistribution controls remain.
- [Public usage and submission instructions](nur.md) document unfree opt-in,
  compatibility expectations, package naming policy and license scope.
- [Registration manifest](nur-registration.json) proposes the `nix-forge` namespace.

## Validation

Both evaluations passed for the local collection:

| Platform | Locked Nixpkgs | Current unstable |
| --- | ---: | ---: |
| x86_64-linux | 27 | 27 |
| aarch64-linux | 25 | 25 |
| aarch64-darwin | 34 | 34 |
| Total | 86 | 86 |

The restricted Linux index query returned 13 entries for each input. This is not
an inventory of every supported package. Machine-readable results are in
[nur-validation/locked.json](nur-validation/locked.json) and
[nur-validation/unstable.json](nur-validation/unstable.json). These checks evaluated
derivation paths. Separately, all 27 native x86_64-linux outputs built successfully;
the metadata and discovery changes preserve their derivation paths.
Targeted repository hooks, Nix formatting, Python lint/type checks, action pinning
and workflow security lint passed.

## Publication boundary

The NUR integration is part of
[combined PR #46](https://github.com/nix-forge/nixpkgs-personal/pull/46).
The overlapping CI-only PR #47 was closed after its changes were incorporated.
PR #46 is the authoritative integration branch.

It preserves the native font checks and build limits, adds font provenance,
corrects Firefox Emoji's Apache 2.0 Nixpkgs license identifier and retains
Noctalia's vendored MIT notice. The combined tree passes 86 evaluations for each
Nixpkgs input. All 86 package/platform derivation paths match the package-only
revision before these metadata and notice fixes.

CI avoids recompiling identical derivations while retaining explicit contracts
and conservatively rebuilding when comparison is unavailable. Six scenarios using
real Nix evaluation verified the build-selection behavior.

The package changes must pass both PR checks and the protected merge queue before publication is complete.
No upstream NUR pull request has been submitted and no binary-cache publication
has been enabled.

The package reorganization and updater refactors belong to the follow-up review.
That review builds on the package and NUR integration in #46. Complete the
upstream NUR submission checklist against the final merged tree before registering.
