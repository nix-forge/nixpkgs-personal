# Jellyfin Subtitle Extract plugin

This package builds the pinned upstream source with .NET 10 for Jellyfin
12.1. Its manifest comes from upstream's `build.yaml`, targets Jellyfin ABI
12.0, and disables Jellyfin's automatic plugin updates so that the running
version stays aligned with the Nix store. The consuming NixOS module copies
the payload into Jellyfin's writable plugin directory.

The upstream source supplies the GPL-3.0 notice. Run
`python3 update.py --dry-run` from the development shell to preview a release,
then `python3 update.py` to refresh its immutable source revision and NuGet
graph. The updater checks the release's build manifest and refuses an ABI,
framework, or artifact change. Build the plugin and validate loading in the
target Jellyfin service before adoption.
