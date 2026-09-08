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
PR #46 merged at `327a24558aec56486e2e82d8ee494a983f133bd2` after
all PR and protected merge-queue checks passed, including three native builds.

It preserves the native font checks and build limits, adds font provenance,
corrects Firefox Emoji's Apache 2.0 Nixpkgs license identifier and retains
Noctalia's vendored MIT notice. The combined tree passes 86 evaluations for each
Nixpkgs input. All 86 package/platform derivation paths match the package-only
revision before these metadata and notice fixes.

CI avoids recompiling identical derivations while retaining explicit contracts
and conservatively rebuilding when comparison is unavailable. Follow-up
[PR #48](https://github.com/nix-forge/nixpkgs-personal/pull/48) adds ten real Git/Nix
regression scenarios, including missing history and failed diffs. It also removes
downloaded executable invocation from the privileged remindctl updater. Five
archive-inspection tests cover that change, with native version verification
retained in the package install check.

PR #48 records exact Nixpkgs revisions and NAR hashes, verifies the locked hash,
and provides readable NUR summaries with source links. Its local locked and
unstable checks each pass all 86 evaluations and return 13 restricted-index entries.
A negative check rejects a mismatched lockfile hash. All final hosted PR checks
passed. Protected queue validation is running against the Nixpkgs update merged
in #49. The package repository now enforces 19 required checks, including both
NUR inputs and the five existing Swift quality, sanitizer and compiler-audit jobs.

The newer package reorganization must pass both PR checks and the protected merge
queue before publication is complete.

No upstream NUR pull request has been submitted and no binary-cache publication
has been enabled.

The package reorganization and updater refactors belong to the follow-up review.
That review builds on the package and NUR integration in #46. Complete the
upstream NUR submission checklist against the final merged tree before registering.
