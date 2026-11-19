# Contributing

This repository publishes reusable package recipes and overlays. Contributions
should work for consumers beyond the maintainer's machines and should not
silently depend on private files, credentials, or local paths.

Before a larger change, open an issue describing the package, upstream source,
license, supported systems, and maintenance plan. Keep pull requests focused.
Explain behavior changes, update package metadata and documentation, and update relevant library tests or static checks.

Run the relevant commands from the README and confirm that the repository's CI
passes. At minimum, run `just check` for changes that affect the flake,
package definitions, overlays, or update tooling. This recipe materializes the
development partition, evaluates checks and validates every exported system in
separate evaluator processes. This preserves coverage while bounding peak memory.

Pull requests and merge groups run static formatting, lint, type, syntax,
dependency/security and documentation checks, Nix library tests, and ordinary
package builds. Add focused `nix-unit` cases for reusable functions under `lib/`.
Tests compare named expressions with expected values or expected errors; do not
add standalone assertion wrappers, module snapshots, behavioral suites, native
runtime checks or project-authored package install tests. Keep module setting
validation in the owning module's `assertions` block.

Preserve upstream software's own test defaults and production safety checks.
Package build phases that execute upstream tests may remain. A successful static
check or library test does not establish runtime, recovery or installation
behavior. See [testing](docs/testing.md) for commands. Security and dependency
findings follow the [dependency-management policy](docs/dependency-management.md).

Do not commit secrets, generated credentials, or large binary artifacts. Use
full immutable references for GitHub Actions and preserve the repository's
least-privilege workflow permissions.

Commits should include a sign-off with `git commit -s`. This records agreement
to the [Developer Certificate of Origin](https://developercertificate.org/).

Submit changes as pull requests against `main`. The maintainer decides whether
the review is sufficient; passing checks and the merge queue are required.

Development dependencies belong in the Nix shell, loaded with direnv or
`nix develop`. Do not install repository tooling with npm, pnpm, Bun, pip or uv,
or create local dependency directories or virtual environments. Keep root
`pyproject.toml` files limited to tool configuration. Application package recipes
retain their own upstream build dependencies inside Nix builds.

## Source filenames

Use lowercase snake_case for Python sources, including executable helpers and
test fixtures. Use lowercase kebab-case for shell helpers and ordinary assets.
Name scripts by their behavior or package phase, such as `post-install.sh`,
rather than extraction ordinals, line numbers or interpolation fragments. Keep
native manifests, language entry points, public package/module identities, real
version numbers and discovery-test filenames stable. An installed command can
keep its hyphenated name when its Python source uses underscores.

Update callers, imports, fixture loaders, source filters and per-file lint
selections when moving a source. Check derived filenames as well as literal
paths, and preserve file permissions.
