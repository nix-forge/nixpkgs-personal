# finder-favorites

`finder-favorites` is an arm64-native command-line tool for declaring and
reconciling the macOS Finder Favorites sidebar. It is designed for Home
Manager, but its JSON interface is independent of Nix.

Apple does not provide a supported API for programmatically managing Finder
Favorites. This tool uses the deprecated `LSSharedFileList` API because it is
the only native interface still shipped with current macOS SDKs. That API is
isolated in a small C adapter so the configuration, planning, transaction, and
recovery code remain independently testable.

## Safety model

- Additive only. Unmanaged favorites are never deleted.
- Identity is based on canonical paths and persistent sidebar item IDs, not
  mutable labels.
- A per-user lock prevents concurrent tool runs.
- Every write uses a private crash-recovery journal.
- Failures trigger rollback, and successful writes are verified from a fresh
  snapshot.
- Network volumes are never mounted and resolution never prompts the user.
- Running as root or through `sudo` is rejected.
- Tests use an in-memory backend and never touch the live Finder sidebar.

Finder itself can still change the sidebar concurrently. If that happens,
rerun `apply`. If a process is terminated during a write, run `recover` before
the next apply.

## Configuration

```json
{
  "schemaVersion": 1,
  "placement": "bottom",
  "entries": [
    {
      "id": "downloads",
      "label": "Downloads",
      "path": "/Users/example/Downloads",
      "onMissing": "error"
    }
  ]
}
```

`onMissing` accepts `error`, `skip`, or `createDirectory`. Configuration is
limited to 1 MiB and 256 entries. IDs and canonical paths must be unique;
labels may repeat.

## Commands

```text
finder-favorites list [--json]
finder-favorites export
finder-favorites plan --config FILE [--json]
finder-favorites check --config FILE [--json]
finder-favorites apply --config FILE [--dry-run] [--json]
finder-favorites recover [--state-directory DIR]
finder-favorites doctor [--json]
```

`check` exits with status 1 when drift exists and 0 when the configuration is
already satisfied. Errors use status 2.

## Compatibility

The package targets macOS 14 or newer and is built for Apple silicon. The
backend is verified by automated bridge tests at build time and should be
treated as compatibility-sensitive because Apple may remove the deprecated API
in a future macOS release. `doctor` reports the active backend and architecture.

## Development quality gate

From the `nixpkgs-personal` flake, run the complete pinned quality suite with:

```console
nix develop --command pkgs/by-name/fi/finder-favorites/Scripts/check-quality.sh
```

The suite checks Swift and C formatting, SwiftLint, strict Swift 5 and Swift 6
compiler modes, complete concurrency checking, Periphery, Clang's full warning
set, clang-tidy, the Clang Static Analyzer, Nix, Bash, YAML, JSON, Markdown,
spelling, XCTest, Address Sanitizer, and Thread Sanitizer. Each compiler and
sanitizer lane has an isolated scratch directory. Set
`FINDER_FAVORITES_RUN_SANITIZERS=0` only for a quicker local iteration.

The shipping Nix compiler is Swift 5.10. Swift 6.2 strict memory-safety mode is
documented as a forward audit rather than a gate because its required `unsafe`
source annotations cannot be parsed by Swift 5.10. The C boundary remains
covered by explicit nullability, strict Clang diagnostics, two static analyzers,
and runtime sanitizers for every non-live code path.
