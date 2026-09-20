# Contributing

This repository publishes reusable package recipes and overlays. Contributions
should work for consumers beyond the maintainer's machines and should not
silently depend on private files, credentials, or local paths.

Before a larger change, open an issue describing the package, upstream source,
license, supported systems, and maintenance plan. Keep pull requests focused.
Explain behavior changes, update package metadata and documentation, and add a
test or check when the package supports one.

Run the relevant commands from the README and confirm that the repository's CI
passes. At minimum, run `nix flake check` for changes that affect the flake,
package definitions, overlays, or update tooling.

Pull requests and merge groups run formatting, repository hooks, dependency
review, CodeQL, flake-lock health, NUR compatibility checks, and the package
test or evaluation matrix. Every major package, overlay, source, metadata, or
update-tool change must add or update an automated test or check. If an
automated test is not practical, record the reason, manual evidence, and a
follow-up plan in the pull request. Security and dependency findings follow
the [dependency-management policy](docs/dependency-management.md).

Do not commit secrets, generated credentials, or large binary artifacts. Use
full immutable references for GitHub Actions and preserve the repository's
least-privilege workflow permissions.

Commits should include a sign-off with `git commit -s`. This records agreement
to the [Developer Certificate of Origin](https://developercertificate.org/).

Submit changes as pull requests against `main`. The maintainer decides whether
the review is sufficient; passing checks and the merge queue are required.
