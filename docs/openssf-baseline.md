# OpenSSF baseline policy

This repository follows the [OSPS Baseline](https://baseline.openssf.org/versions/2026-08-28)
version 2026.08.28. The policy covers package recipes, overlays, NUR metadata,
source updates, CI, and documentation.

## Project scope and releases

nixpkgs-personal is a public package collection and NUR-style submission. It
does not currently publish compiled GitHub release assets or official GitHub
releases. Package outputs are built by consumers from reviewed source
expressions and fixed hashes. A future source release would use an immutable
tag, a change log, integrity evidence, security review, and the support policy
recorded here. The SLSA scope and future builder contract are documented in
[docs/slsa.md](slsa.md).

This repository is part of the related projects listed in the
[nix-forge project security contract](https://github.com/nix-forge/.github/blob/main/PROJECTS.md).
Related repositories enforce the same minimum security contract or a stricter
one for their own code and release surfaces.

## Change and build controls

Every commit must carry a matching Signed-off-by trailer. The DCO file defines
the certificate and .github/workflows/dco.yml checks proposed non-merge commits
on pull requests and merge-group refs.

All workflows start with empty default permissions. Jobs grant only the scopes
they need, checkout does not persist credentials, and actions use full commit
SHAs. Pull requests and merge groups run lockfile validation, dependency
review, CodeQL for supported source languages, NUR checks, and package tests
before protected main can advance.

Use [CONTRIBUTING.md](../CONTRIBUTING.md) and the package test commands for the
affected recipe. The baseline evidence set is:

    nix flake check --show-trace
    python3 tests/test_nur_check.py
    python3 tests/run-package-tests.py

Package changes include an evaluation or runtime assertion where the package
has behavior to test. Source hashes and license metadata are reviewed with
updates. Never commit credentials, private source archives, or generated
secrets.

## Release and dependency controls

Flake inputs, package source hashes, language lockfiles, and NUR metadata are
reviewed with their security and licensing impact. Dependency review blocks
new low-or-higher severity vulnerabilities. CodeQL and SCA findings must be
fixed before a future release unless a reviewed suppression records why a
finding is not exploitable.

If this repository begins publishing releases, the maintainer will tag a
reviewed main commit, publish a scoped change log, record the source commit,
publish checksums and a signed manifest, identify the release actor and
workflow, explain verification, and state the support window. Package outputs
remain reproducible build inputs, not opaque binaries uploaded by the release
job.

## Governance and vulnerability response

The maintainers listed in [GOVERNANCE.md](../GOVERNANCE.md) own repository
administration, Actions secrets, Pages, dependency policy, and future releases.
Sensitive access is granted after review of the contributor's history and
intended responsibility. New maintainers receive the narrowest role needed.

Report vulnerabilities through [SECURITY.md](../SECURITY.md) or GitHub private
vulnerability reporting. The maintainer acknowledges reports within three
business days and provides an initial assessment within seven days. Public
disclosure follows a fix or documented mitigation. [security/vex.json](../security/vex.json)
records reviewed non-affectability statements. Support rules are in
[SUPPORT.md](../SUPPORT.md).

The operating procedures for [dependency management](dependency-management.md)
and [secret management](secret-management.md) are part of this policy. They
define the review, release-gate, storage, access, and rotation requirements
used to support the controls below.

## Control evidence

| Control area | Evidence |
| --- | --- |
| Least-privilege CI and trusted inputs | Empty default permissions, job scopes, pinned actions, quoted inputs, and no fork secrets |
| Releases and change logs | This release policy and package update history |
| Dependencies | flake.lock, package hashes, language lockfiles, dependency review, and CodeQL |
| Build and test instructions | [CONTRIBUTING.md](../CONTRIBUTING.md) and package test scripts |
| Governance | [GOVERNANCE.md](../GOVERNANCE.md) |
| Contributor legal agreement | [DCO](../DCO) and .github/workflows/dco.yml |
| Security assessment | [THREAT_MODEL.md](../THREAT_MODEL.md) |
| Vulnerability response | [SECURITY.md](../SECURITY.md), private reporting, advisories, and [security/vex.json](../security/vex.json) |
| Public interfaces and release identity | Package metadata, NUR contract, reviewed commits, and future signed manifests |
| Support lifecycle | [SUPPORT.md](../SUPPORT.md) |

Review this policy when package trust, source acquisition, CI, or release
behavior changes.
