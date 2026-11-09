# BookOrbit

This package builds BookOrbit 3.6.0 from the source revision pinned in
`package.nix`. It builds the client and server with pnpm, then installs the
production server dependencies, client assets, database migrations, and KOReader
plugin. Upstream licenses the application under AGPL-3.0-only.

`bookorbit` starts the production server. `bookorbit-migrate` runs the database
migration entrypoint. The consuming service supplies runtime settings and
writable state; the package does not provision a database or start the service.
Install checks validate both JavaScript entrypoints and the migration payload.
They do not test database migrations or a running application.

Updates are manual. Review the source revision, version, source hash, and pnpm
dependency hash together, then build the package and check service startup and
migration compatibility before deployment. There is no unattended updater because
source and dependency updates need that application-level review.

Builds disable interactive progress rendering with `CI=true` and `TERM=dumb`.
The compiler flags, Swagger metadata generation, and TypeScript checks remain
unchanged.

The selected SWC native carrier is materialized during the build with the pinned
upstream verifier. It validates the retained sections, frame bounds, architecture,
SHA-512, and BLAKE3 before atomically installing the verified raw addon in the
build tree. This avoids the carrier cache loader's incompatible ancestor-owner
check in Nix user namespaces. On Darwin, fixtures use the declared Nix codesign tool inside the sandbox.
The verifier runs its upstream carrier, format, and integrity tests. On Linux,
PRoot supplies a private owned filesystem view for the latter suites inside the
existing Nix sandbox, preserving the invoking UID/GID and the upstream ancestor
ownership checks without requiring a nested user namespace. The harness does
not establish runtime cache behavior.

Review this adapter when SWC changes its carrier format or publishes raw addons.
Remove it once the unmodified selected native binding loads and the full compiler
checks pass in the Nix sandbox. The verifier's source pin and Cargo closure must
be reviewed together when updating the tool.
