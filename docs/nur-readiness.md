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

[PR #47](https://github.com/nix-forge/nixpkgs-personal/pull/47) adds the reusable CI,
entry point, evaluator, documentation and scheduled unstable checks to the existing
published package tree. That tree has 35 supported package/platform combinations;
both NUR CI jobs passed. Its native package build and Swift checks remain intact.

The expanded collection and provenance edits are included in the package follow-up
review. They are separate from PR #47. Before registering the expanded collection,
merge the intended package changes and pass the existing native CI builds on that
revision. Complete the upstream NUR submission checklist
against that published tree. No upstream NUR pull request has been submitted and
no binary-cache publication has been enabled.
