# Moonfin

The `moonfin` package builds the pinned Moonfin Core release from source on
Linux with a versioned Flutter SDK, a pinned Dart dependency lock, and pinned
Git dependencies. It
links the native plugins against Nixpkgs libraries and supplies a desktop entry
and icon. Flutter's prebuilt Linux engine, bundled fonts, and WebAssembly
assets remain declared binary inputs. On macOS it preserves the signed upstream
app under `Applications/Moonfin.app`.

Moonfin's Seerr feature uses the Moonbase plugin on the Jellyfin server. Each
user signs in once under Settings > Integrations > Seerr. Keep that session in
Moonfin's private application data rather than a Nix derivation. Package
updates follow the pins in `source.nix`, not an in-app download.

Run `python3 update.py --dry-run` from the development shell to preview a
stable release, then `python3 update.py` to refresh the immutable source
revision, upstream Flutter lock, exact Git dependency hashes, and macOS asset
hash together. The selected release must contain the expected macOS asset.
The updater also refuses a Flutter SDK requirement above the pinned Linux
builder. Build on Linux and macOS before accepting an update; review native
plugin changes if either build fails. The Linux install check verifies
the executable, desktop entry, and icon; it does not exercise the GUI.

Upstream releases: <https://github.com/Moonfin-Client/Moonfin-Core/releases>
