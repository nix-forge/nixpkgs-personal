# Scrypted HomeKit plugin

This package extracts the published `@scrypted/homekit` npm artifact, including
its Scrypted plugin zip and license. It does not create HomeKit accessories or
pair them with Apple Home. Consumers deploy the pinned metadata and zip through
Scrypted's authenticated plugin endpoint.

The pinned release is 1.2.71. Its official npm metadata names public commit
`e239a6c297165012ca3899f6a6f8ea5aac5063fc`, whose checked-in HomeKit manifest
still declares 1.2.70. The newer default-branch manifest declares 1.2.71, but
that does not establish the published release's source identity. The exact
published commit also requires `../../homekit-scratchpad/HAP-NodeJS`, which is
absent from its public tree. Building a different dependency closure and naming
it 1.2.71 would not establish equivalence with the published plugin.

This package preserves the upstream-built minified bundle and its
`obfuscatedCode` provenance. The official archive's published SHA-512, package
identity, plugin type and ZIP inventory are checked during release review; the
installed package check validates metadata and ZIP integrity without executing
the plugin. Convert to a source build when upstream publishes the matching
manifest and complete dependency revisions, and verify deployment and pairing
compatibility before replacing an existing installation. The earlier
[release-source review](../../../../docs/homekit-source-research.md) records the
same class of source gap in historical releases.

Review the plugin release, Scrypted server compatibility, and any network or
pairing changes before updating the source pin. This package has no unattended
updater because HomeKit pairing state lives outside the Nix store.
