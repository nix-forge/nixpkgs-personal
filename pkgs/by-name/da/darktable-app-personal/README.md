# Darktable app for macOS

This package places the Nixpkgs Darktable executable and icon in a macOS app
bundle. Consumers may override the `darktable` input to select a different
Nixpkgs build. The wrapper does not contain host settings.

Build it on macOS with `nix build .#darktable-app-personal`.
