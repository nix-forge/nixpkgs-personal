# PersonalMonitor, packaged as vorssaint

`nix build .#vorssaint` now builds **PersonalMonitor**, an unofficial variant of
Vorssaint. The public package attribute and `bin/vorssaint` command remain stable;
the application is `Applications/PersonalMonitor.app`.

The variant uses an independently drawn icon, the bundle identifier
`io.github.ianhollow.personalmonitor`, matching helper identifiers, and ad-hoc
signing. It preserves upstream copyright credits and installs both GPL and
`TRADEMARKS.md` notices. These changes follow the
[pinned branding policy](https://github.com/vorssaint/vorssaint-utils/blob/b686b87f8933a69ac88e7a4f8d8976c083ed6cd1/TRADEMARKS.md).
It is not an official release or endorsed by the upstream maintainer.

Updates are managed through Nix. Automatic and manual in-app update downloads
are disabled, so an upstream release cannot replace this application. Upstream
release-showcase downloads are disabled too. Upstream donation/community links
continue identifying the upstream project; they do not represent this package.

Privileged fan control is unavailable in this ad-hoc signed build. Upstream's
IPC requires its Developer ID team signature, which this package cannot supply.
The package removes that team identity, rejects privileged IPC peers, and reports
the feature as unavailable. It does not weaken authentication to a freely
spoofable bundle identifier. A signed distribution would need its own trusted
signing identity and a separate review of the helper integration.

Because the bundle identity changed, macOS treats this as a separate application.
Existing application permissions and preferences do not automatically migrate.
The package does not unregister or modify an existing upstream installation.

Run `python3 update.py --dry-run` to preview a pin update. `rebrand.py` applies
checked identity and updater changes after the Swift compatibility patch. Review
upstream branding, helper requirements, and update code on each source update.
Native macOS checks compile the app and run the helper self-test; launching the
GUI and verifying macOS permissions require a separate native smoke test.

## Compiler checks and optimization

The Now Playing adapter enforces complete concurrency diagnostics with warnings
as errors in Swift 5 language mode. The full application and fan helper still
need an upstream actor migration. A separate diagnostic command checks all three
targets and propagates compiler errors, while continuing to inspect the remaining
targets:

```console
SWIFTC=swiftc Scripts/check-concurrency.sh /path/to/patched-source
```

Supply the unpacked source after the package's compatibility patch and
`rebrand.py`. Set `VORSSAINT_WARNINGS_AS_ERRORS=1` to make application and helper
warnings fail too. This lane is diagnostic and is not an ordinary package build
gate. On the pinned source, Swift 5.10.1 reports 21 application errors and
366 warnings before stopping; later source files can contain further findings.
Adding `@MainActor` to `AppDelegate` alone breaks ordinary compilation at
`CommandBarCatalog` call sites, so that change requires migrating the callers.
Swift 6.3.3 also reports an expression-diagnostic failure in
`MenuPanelView.swift`. The helper has non-Sendable captures in its serial-queue
callbacks. The package keeps its logger on the controller and reads startup
arguments through Foundation, removing four pinned-toolchain diagnostics without
changing queue or XPC behavior. Complete helper checking still reports 19
Swift 5.10 warnings, including callback captures and the imported
`mach_task_self_` global. The existing locked `AsyncResultBox` compatibility
bridge still uses `@unchecked Sendable`; a complete migration must review the AVFoundation values
and closure it transfers, not just the box's lock. No new unchecked conformances
or warning suppressions are added.

The helper release build uses whole-module optimization. An arm64 macOS
comparison reduced its executable from 434,112 to 360,912 bytes with Swift
5.10.1 and from 402,512 to 342,272 bytes with Swift 6.3.3. All baseline and WMO
helper fixture selftests passed. With Swift 6.3.3, three-build median wall time
fell from 3.71 to 2.67 seconds; peak resident memory increased from 201 to 246 MB.
These measurements do not establish application startup or fan-control latency.

```console
Scripts/benchmark-optimization.sh /path/to/patched-source
```

The script alternates baseline and WMO builds and reports wall time, CPU time,
peak resident memory, executable size, and warm helper selftests. Set
`VORSSAINT_BENCHMARK_APP=1` to compare application builds too. It never launches
the application, loads the Now Playing adapter, or starts fan control.
`SWIFTC` selects the compiler; `BENCHMARK_BUILD_RUNS` and `BENCHMARK_TEST_RUNS`
control the default three builds and twenty warm selftests per mode. Temporary
outputs are removed on exit. The application keeps its existing optimization
settings until its own build and runtime evidence justifies a change.
