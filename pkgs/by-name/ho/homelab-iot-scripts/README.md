# Homelab IoT scripts

Compiled Node.js helpers for Homebridge initialization, UI authentication checks,
and Scrypted authentication, settings and plugin installation. Consumers invoke
these modules with Node.js 24. The package preserves the module filenames at its
output root for nix-homelab service integration.

This first-party source is maintained in this directory. There is no upstream
release updater. Update development dependencies through the lock file and refresh
`npmDepsHash` together. Builds run TypeScript, lint, formatting and behavior tests.
