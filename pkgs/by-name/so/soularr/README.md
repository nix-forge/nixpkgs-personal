# Soularr

Native CLI-only package of [Soularr v1.2.3](https://github.com/mrusse/soularr/tree/v1.2.3),
which acquires Lidarr wanted albums through slskd. The optional web UI is not installed.

Build with `nix build .#soularr`. Supply a private runtime `config.ini` with
`--config-dir`; keep API credentials outside the Nix store. Use `--var-dir` for
writable retry/import state. Under a serialized systemd oneshot, `--no-lock-file`
avoids stale upstream PID files. The caller must bound overall runtime and use
consistent, writable download paths for slskd, Soularr and Lidarr.

`shared-client.patch` repairs v1.2.3 behavior for a shared client: queue inspection
fails closed; cancellations preserve directories and other transfers; enqueue
rejects existing transfers and local directory collisions; owned transfers can
retry; failed peers receive a two-hour cooldown; import polling is bounded; fatal
processing exits unsuccessfully. Selected-release mode stays on that edition.
The release already fixes search-timeout units; that obsolete local hunk is
retired. Retain its filename-based partial-enqueue validation, while uncertain
requests stop for journal reconciliation instead of cancelling transfers ad hoc.
Both upstream Lidarr transport exception types fail closed. Cancelled, aborted,
orphaned or unconfirmed imports fail without clearing ownership state.
A persistent enqueue journal recovers interrupted/partial requests, and only
owned transfer IDs are removed. Failed partials are quarantined without
removing another consumer's files. Global completed-transfer cleanup is disabled. Remove each patch hunk once an
upstream release supplies equivalent behavior and these regression checks pass.

The slskd API has no atomic consumer ownership operation. Preflight collision
checks reduce interference but cannot eliminate simultaneous identical requests
by independent clients. Avoid concurrent consumers requesting the same album.
Import failures preserve files and remain in the upstream failed-import denylist
for inspection; resolve the import problem before clearing its entry.

Build checks exercise the patched source against mocked APIs, including queue
failure, transfer ownership, retry and selected-release behavior. The installed
CLI is also exercised with `--help`. Live transfer/import validation belongs to
the deployment, since it needs private accounts and network access.
