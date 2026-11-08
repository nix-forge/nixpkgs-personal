# Navidrome lyrics plugin

This package builds the pinned upstream Rust source as WASI WebAssembly and
packs it with the matching source manifest into `nd-lyrics.ndp`. Cargo
dependencies, including Navidrome's plugin SDK, have a fixed-output hash.
The install check verifies the archive, manifest version, and WebAssembly
header; Navidrome performs the plugin validation.

The plugin requires Navidrome 0.63.0 or newer. Add this package to
`services.navidrome.plugins`, include `nd-lyrics` in `LyricsPriority`, and
configure its providers through Navidrome's plugin settings. It fetches lyrics
when a client requests them. Navidrome's current web player does not display
lyrics returned by plugins, so use a compatible OpenSubsonic client.

For updates, review the [upstream release](https://github.com/J0R6IT0/navidrome-lyrics-plugin/releases)
and its permissions, then update the version and source and Cargo hashes in
`source.nix`. Build the package and validate the archive with Navidrome's
`plugin validate` command before selecting the new release.
This update stays manual because plugin permissions and Navidrome compatibility
need review with each release.
