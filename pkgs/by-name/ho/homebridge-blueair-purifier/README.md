# Homebridge Blueair purifier

This package builds `homebridge-blueair-purifier` 1.2.1 from its tagged source.
Upstream lists the Blue Pure 511i Max as a tested model. The plugin uses
Blueair's cloud account and does not provide a local device protocol.

The pinned manifest and lock update runtime `lodash` to 4.18.1, outside
upstream's 4.17 range, to address the reported code-injection and prototype
pollution advisories. The production dependency audit has no reported findings.
`redact-api-logs.patch` removes debug logging of environment variables,
Homebridge configuration, account names, and API request or response bodies;
those values can contain credentials or tokens. The build checks the installed
plugin entrypoint, configuration schema, and custom UI server.

Account credentials and discovered device identifiers belong in Homebridge's
protected writable state, not the Nix store. The plugin's own README warns
that PM2.5 readings can be incorrect because of limitations in the Blueair API.
Check that value against the Blueair app before using it for automations.

Updates need a review of the cloud login flow, dependency lock, log handling,
device behavior, and UI assets. There is no unattended updater because those
checks require a real Blueair account and purifier.
