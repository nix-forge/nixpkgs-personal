# Threat model

## Scope

This model covers package expressions, overlays, source acquisition, NUR
metadata, tests, documentation, and repository automation. It does not cover
the consumer's machine or upstream services.

## Assets and actors

Assets include source hashes, package metadata, license declarations, generated
outputs, dependency pins, and CI access. Contributors and pull requests are
untrusted. Maintainers approve changes and control repository and future release
settings. Nix evaluates package code and fetches sources according to reviewed
expressions.

## Trust boundaries

Upstream source archives, the Nix evaluator, generated package outputs, and
GitHub Actions are separate boundaries. A source hash binds an expected
archive, but it does not replace license or vulnerability review. Pull-request
jobs must not receive repository secrets.

## Main threats and controls

| Threat | Control |
| --- | --- |
| A package fetches unintended source | Reviewed fixed hashes, source tests, and dependency review |
| A recipe ships malicious or vulnerable behavior | CodeQL, SCA, package tests, review, and release gating |
| License or NUR metadata misleads consumers | Metadata tests, review, and documented package policy |
| CI credentials reach pull-request code | Empty default permissions, job scopes, pinned actions, and no fork secrets |

Review this model when changing source acquisition, package trust, evaluator
behavior, CI permissions, or release automation.
