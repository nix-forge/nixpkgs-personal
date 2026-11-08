# AudioMuse-AI Navidrome plugin

This package builds the pinned v12 upstream source using Nixpkgs' Navidrome
plugin recipe. It restricts the plugin manifest's required HTTP hosts to
`127.0.0.1` for a local AudioMuse-AI API and verifies the packed `.ndp`
contains that permission. An unexpected upstream permission fails the build.

Updates are manual because the source version, Go vendor hash, permission
shape, and Navidrome plugin compatibility must be reviewed together. The
package depends only on the upstream Nixpkgs plugin recipe, so it can be used
outside this homelab configuration.

The public package installs the cross-built WASI archive through a native Linux
packaging stage. Its platform metadata describes the Navidrome host, while the
internal compiler derivation retains its WASI target. Installation checks verify
archive integrity, the WebAssembly header, loopback permission and license.

`passthru.wasmSource` exposes the patched source used by the WASI compiler,
so source audits and template checks can inspect that stage independently.
