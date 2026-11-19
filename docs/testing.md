# Testing and static checks

Run `just test` to build `checks.<system>.lib-tests`, or use the pinned runner
from `nix develop --command nix-unit --flake '.#libTests'`. Library cases live
under `lib/tests/` and exercise production functions under `lib/` using named
`expr`/`expected` and `expectedError` values. There are no standalone assertion
wrappers or behavioral, snapshot, integration, VM, native-runtime or non-Rust
fuzz suites maintained in this repository.

Run `just check` for flake/output evaluation, `just lint` for Python static
analysis, and `nix develop --command javascript-check` for TypeScript, Oxlint and
formatting. Nix supplies all development dependencies; no package-manager install,
local dependency directory or Python virtual environment is needed.
`pyproject.toml` contains tool configuration only. Nix checks retain source-pin metadata validation, generated package
hook Bash/Python syntax checking, JavaScript quality, documentation, treefmt
and repository hooks. Static utilities live under `scripts/` and `flake/dev/`.

Package builds retain upstream software's own test defaults. Project-authored
install checks and test passthru outputs have been removed. Production input
validation, required compatibility handling, source filters and runtime safety
checks remain. Module assertions may reject invalid option combinations; they
must not read back fixed selections as tests.

Use `nix develop` for pinned tools. Include new source files deliberately in
Git's source view before evaluating a flake. Run native checks on the matching
platform and distinguish evaluation, build and activation evidence. Static and
library checks do not prove application runtime or recovery behavior.
