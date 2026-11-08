# Homebridge LG ThinQ fork

This packages `@mp-consulting/homebridge-lg-thinq` 1.1.5 from its tagged source.
The previously required local `brace-expansion` lockfile replacement has been
retired.
The fork declares
Node 24 and Homebridge 2 support, and its
September 2026 changes repair LG sign-in and washer status behavior. Washer and
dryer status is supported; its README does not claim direct laundry controls.

The Nix build compiles the TypeScript plugin and copies its UI assets. The
install check loads the installed entrypoint. `homebridgePluginName` records the
scoped npm directory for Homebridge consumers. Account tokens and appliance IDs
belong in Homebridge's protected writable state, not this package.

Updates require review of the LG authentication flow, source lockfile, engine
ranges, supported appliance behavior, and UI assets. There is no unattended
updater because those checks need account and device testing.
