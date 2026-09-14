# Dependency management policy

This policy applies to package expressions, overlays, NUR metadata, Nix and
language lockfiles, source hashes, GitHub Actions, and package test tooling in
nixpkgs-personal. Dependency and source updates are part of package security
review.

## Inventory and provenance

The authoritative records are `flake.lock`, nested language lockfiles, fixed
source hashes in package expressions, NUR metadata, and immutable action
references in `.github/workflows/`. Each update identifies the upstream source,
revision or archive, expected hash, license, and material transitive changes.

Dependabot keeps supported ecosystems visible. Dependency-review, CodeQL,
flake-lock health, NUR compatibility checks, and package tests run in CI.
These checks cover known vulnerabilities, supported source languages, lockfile
freshness, metadata, and the package behavior exercised by the repository.

## Selection and review

Maintainers review upstream provenance, maintenance status, security
advisories, licensing, reproducibility, platform support, and package behavior.
Source hashes are changed only with an intentional source update and are
verified against the reviewed upstream artifact. Action updates use immutable
commit SHAs. Package changes include an evaluation or runtime assertion when
the recipe has behavior that can be tested.

## Release gate and exceptions

Before a future release, applicable dependency-review, CodeQL, lock-health,
NUR, package, and test checks must pass. A high- or critical-severity finding,
an unreviewed license problem, or a failed provenance check blocks release.
The only exception is a reviewed, time-bounded pull-request record that names
the component, explains why it is not exploitable here, assigns an owner, and
gives a remediation date. `security/vex.json` records reviewed
non-affectability statements in OpenVEX form; it does not waive an affectable
finding.

## Update and rollback

Updates are evaluated on the supported systems and representative package
tests. A regression is rolled back by reverting the lockfile, source hash, or
expression change, then tracked with a follow-up issue. Emergency security
updates use the smallest safe change and receive normal review retrospectively
if immediate action is required.
