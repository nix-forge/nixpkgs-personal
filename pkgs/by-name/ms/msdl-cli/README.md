# msdl-cli

This package builds the open-source MSDL command-line client from a pinned
upstream commit. It obtains short-lived consumer Windows ISO links from
Microsoft's download service. The ISO bytes are downloaded from Microsoft's
CDN, not from MSDL.

The client uses an undocumented Microsoft web flow, so link discovery can stop
working when Microsoft changes its site. It does not verify ISO contents or
license Windows. Consumers must check the exact filename, Microsoft's
published SHA-256, and the required WIM image before installing a guest.

The client normally sends anonymous telemetry and may contribute link metadata
to the MSDL service. Set `MSDL_NO_TELEMETRY=1` and
`MSDL_NO_CONTRIBUTE=1`, and pass `--no-contribute`, when neither is wanted.

Upstream: <https://github.com/starkSV/windows-iso-downloader>

Source updates are manual. Review the CLI changes to Microsoft's link flow,
then update the commit, source hash, Go vendor hash, and dated version in
`source.nix`. Build and exercise link discovery before accepting a new pin.
