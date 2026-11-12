# Actual CLI

Builds the official CLI and Node API from the same source, lockfile and offline
cache as nixpkgs `actual-server`. No separate npm installation is required.

The upstream CLI supports `ACTUAL_PASSWORD_FILE`, `ACTUAL_SESSION_TOKEN_FILE`
and `ACTUAL_ENCRYPTION_PASSWORD_FILE` for runtime credentials. The package
follows the source version and dependency cache of nixpkgs `actual-server`.

Run `actual-cli --help`. Deployments should supply credentials through runtime
files and keep the local SQLite cache on encrypted storage. API access is not
inherently read-only; granting a token grants its associated user's permissions.
