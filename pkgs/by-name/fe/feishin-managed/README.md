# Managed Feishin

Feishin with declarative account and player settings, native macOS title controls, and mpv lifecycle integration. The package follows the incoming Nixpkgs Feishin version. Build-time substitutions fail when upstream integration points change.

The scripts compile with strict TypeScript checks and run managed-login tests during the build. Darwin titlebar and player interaction still require native runtime checks. This variant keeps the upstream license and metadata. Update it through Nixpkgs; it has no independent source updater.
