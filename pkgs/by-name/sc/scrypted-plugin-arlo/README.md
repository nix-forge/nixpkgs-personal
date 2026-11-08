# Scrypted Arlo plugin

This package builds `@scrypted/arlo` 0.11.54 from its
[public development commit](https://github.com/scryptedapp/arlo/commit/64b2f5284d1a538dcf191a5619cbc00b6b789fd4),
which matches the `gitHead` in the [release metadata](https://registry.npmjs.org/@scrypted/arlo/0.11.54). The matching
upstream lockfile pins the JavaScript build tools; `scrypted-webpack` assembles
the Python source into `dist/plugin.zip` in the Nix build. The resulting zip
has the same 28 file names and SHA-256 content hashes as the published release
zip. It does not install the plugin into a Scrypted
server or supply Arlo account credentials. Consumers can submit the pinned
metadata and zip through Scrypted's authenticated plugin deployment endpoint.
The install check rejects non-source payloads in that zip so its `fromSource`
provenance remains accurate when the release is updated.

The plugin requests Python 3.12 and installs its own Python requirements at
runtime. Review the bundled requirements, wheel availability on each target
architecture, and Scrypted server compatibility before updating the source commit.
That review is why this package intentionally has no unattended updater.
