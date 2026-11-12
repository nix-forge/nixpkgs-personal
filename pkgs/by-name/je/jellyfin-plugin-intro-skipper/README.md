# Jellyfin Intro Skipper plugin

This package builds the pinned upstream source for Jellyfin 12.1. Its dashboard
is built from locked pnpm dependencies and embedded in the .NET 10 assembly.
The consuming NixOS module copies the resulting DLL into Jellyfin's writable
plugin directory and supplies Jellyfin FFmpeg so the plugin can use Chromaprint
for fingerprinting.

The source supplies the GPL-3.0 notice. Updates are manual: review a new tag's
Jellyfin compatibility and web assets, update `source.nix`, regenerate
`deps.json` with the package's `fetch-deps` script, then build and validate the
plugin before changing the service configuration.

The install check starts the selected Jellyfin server with a disposable data
directory, loads the installed plugin DLL and requires its exact ID, version
and Active state. It verifies the selected server version and assembly/service
loading without touching a running installation or user libraries. This covers
server API compatibility, not media fingerprinting or a live database upgrade.
