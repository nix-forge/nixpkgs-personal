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

Do not commit secrets, generated credentials, or large binary artifacts. Use
full immutable references for GitHub Actions and preserve the repository's
least-privilege workflow permissions.

Commits should include a sign-off with `git commit -s`. This records agreement
to the [Developer Certificate of Origin](https://developercertificate.org/).

Submit changes as pull requests against `main`. The protected branch requires
review, passing checks, and the merge queue before changes are accepted.
