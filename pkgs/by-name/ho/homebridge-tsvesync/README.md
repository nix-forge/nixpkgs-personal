# Homebridge VeSync

This packages `homebridge-tsvesync` 1.7.2. Upstream lists the Levoit Vital 200S
and its power, fan, mode, air quality, and filter status controls. It uses the
VeSync cloud account; this recipe contains no credentials or device identifiers.

The package adds optional `usernameFile` and `passwordFile` settings. Each path
points to a private runtime file. File values take precedence over inline values,
so a service can keep account credentials out of Homebridge's `config.json`.
Missing files fail closed. The install check exercises file precedence and
missing-file behavior.

The v1.7.2 source has no lockfile. `package-lock.json` was generated from its
unchanged `package.json` with npm 11 using
`npm install --package-lock-only --ignore-scripts --no-audit --no-fund`. Nix
fetches that resolution with a fixed dependency hash, builds the TypeScript
plugin, and checks that its installed entrypoint loads.

For updates, regenerate the lock from the selected tagged manifest, review the
runtime dependency changes and VeSync authentication behavior, then build and
test on the target architecture. There is no unattended updater because the
upstream source lacks a lock and device compatibility needs manual review.
