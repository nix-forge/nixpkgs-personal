# NUR readiness

Prepared on 2026-09-07, America/Los_Angeles. NUR registration has not been submitted.

## Implemented

- A root `default.nix` forwards caller-supplied `pkgs` to the package registry.
- CI runs the pinned NUR restricted evaluator and a separate three-platform
  compatibility check against locked Nixpkgs and current `nixos-unstable`.
- Reports record the evaluated checkout, resolved Nixpkgs revision and NAR hash.
  The locked input's hash is verified. Job summaries show platform totals and
  source links, with JSON artifacts available for reproduction.
- Supported packages must declare a license; unfree packages must explicitly
  declare source provenance. Precompiled Apple and historical emoji fonts now
  declare `binaryBytecode`; Mutant Standard compiled from source declares
  `fromSource`. Existing upstream licenses and redistribution controls remain.
- [Public usage and submission instructions](nur.md) cover unfree opt-in,
  compatibility expectations, package names and license scope.
- [Registration manifest](nur-registration.json) proposes the `nix-forge` namespace.

## Public validation

The NUR integration merged in [PR #46](https://github.com/nix-forge/nixpkgs-personal/pull/46).
The final hardening merged in [PR #48](https://github.com/nix-forge/nixpkgs-personal/pull/48)
at `2ff7ef7da57c97c782d6f9b16dd24d01ce89dff3`, after all PR and protected merge-queue checks passed.
The queue included the Nixpkgs update from PR #49.

The [final queue run](https://github.com/nix-forge/nixpkgs-personal/actions/runs/34192447944)
passed both NUR inputs:

| Platform | Locked Nixpkgs | Current unstable |
| --- | ---: | ---: |
| x86_64-linux | 27 | 27 |
| aarch64-linux | 25 | 25 |
| aarch64-darwin | 34 | 34 |
| Total | 86 | 86 |

Each restricted Linux index returned 13 entries. That index is not an inventory
of every supported package. These NUR checks evaluate derivation paths; native
Linux and macOS build jobs provide separate build and contract coverage.

The locked input was `801bef6abd86b91e51083066b83fb354a11fc640`, with NAR hash
`sha256-hLD4l3QOGBQhkVp3mQ2lJ/YbEi99qUgKapb40KovZ88=`. Unstable resolved to
`dc5d91f840324650bac8c379428c7037a416959a`, with NAR hash
`sha256-VaWGJ6+cIYN2erfSecbRV+4ljI185Ty2wUrXyvQbgOw=`. The pinned NUR evaluator
revision is `6e73a28249bbd53525bc1a7b385fcf3413c4e056`.

The earlier final PR run also passed both inputs with the preceding locked
Nixpkgs revision, `3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2`.
A local negative check confirmed that a mismatched lockfile hash is rejected.
The linked GitHub Actions runs retain the JSON evaluation artifacts and readable
job summaries for these public revisions.

PR #48 merged with 19 required checks, including both NUR inputs, native
builds, analysis and the five existing Swift quality, sanitizer and compiler-audit
jobs. Ten real Git/Nix scenarios cover build selection and missing history;
12 fetch-retry scenarios cover recovery and refusal. Five archive-inspection tests
verify the safer remindctl updater. It no longer runs downloaded executables in
the privileged update job; native package checks retain executable version testing.

## License review and local work

The integration preserves native font contracts, corrects Firefox Emoji's Apache
2.0 Nixpkgs license identifier and retains Noctalia's vendored MIT notice. All 86
package/platform derivation paths were unchanged by the metadata and notice fixes
relative to the package-only revision used for that comparison.

The initial local collection also passed 86 evaluations per input. Those earlier
results remain in [nur-validation/locked.json](nur-validation/locked.json) and
[nur-validation/unstable.json](nur-validation/unstable.json). They did not build
later unpublished package additions. Local reorganization and other pre-existing
edits remain separate from the published migration.

No upstream NUR pull request has been submitted and no external binary-cache
publication has been enabled. The direct flake remains the primary interface.

## Package reorganization follow-up

The separately reviewed reorganization keeps recipes and their helpers in 39
independent package directories. It adds Finder Favorites quality and sanitizer
coverage, and extends build-selection regression coverage to 14 scenarios.
Package isolation, 19 updater imports, 34 package unit tests and three helper-drift
tests pass. Linux validation covers all 27 public outputs on the merged Nixpkgs
input. Against PR #48, eight unchanged derivations skip rebuilding and 19 changed
derivations pass their native build commands. All 86 supported platform exports
and both NUR inputs evaluate successfully. Hosted ARM and Darwin builds remain
part of this follow-up's required validation.

Complete the upstream NUR submission checklist against the final merged tree
before registering. The direct flake remains usable independently of registration.
