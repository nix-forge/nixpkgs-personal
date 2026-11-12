# MetaBrainz Spicetify extension

This package compiles the context-menu extension from TypeScript and installs
`metabrainz.js` for Spicetify. It contains no Spotify account or host settings.
The consuming Home Manager module selects the extension and configures Spotify.

Startup subscribes to Spicetify's replayable webpack-loaded event. Menu selection
and clicks read the URI and lookup APIs when needed, so later API initialization
does not require a readiness timer.

Build with `nix build .#metabrainz-spicetify-extension` from this repository.
