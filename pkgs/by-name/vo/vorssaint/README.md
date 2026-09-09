# PersonalMonitor, packaged as vorssaint

`nix build .#vorssaint` now builds **PersonalMonitor**, an unofficial variant of
Vorssaint. The public package attribute and `bin/vorssaint` command remain stable;
the application is `Applications/PersonalMonitor.app`.

The variant uses an independently drawn icon, the bundle identifier
`io.github.ianhollow.personalmonitor`, matching helper identifiers, and ad-hoc
signing. It preserves upstream copyright credits and installs both GPL and
`TRADEMARKS.md` notices. These changes follow the
[pinned branding policy](https://github.com/vorssaint/vorssaint-utils/blob/b686b87f8933a69ac88e7a4f8d8976c083ed6cd1/TRADEMARKS.md).
It is not an official release or endorsed by the upstream maintainer.

Updates are managed through Nix. Automatic and manual in-app update downloads
are disabled, so an upstream release cannot replace this application. Upstream
release-showcase downloads are disabled too. Upstream donation/community links
continue identifying the upstream project; they do not represent this package.

Privileged fan control is unavailable in this ad-hoc signed build. Upstream's
IPC requires its Developer ID team signature, which this package cannot supply.
The package removes that team identity, rejects privileged IPC peers, and reports
the feature as unavailable. It does not weaken authentication to a freely
spoofable bundle identifier. A signed distribution would need its own trusted
signing identity and a separate review of the helper integration.

Because the bundle identity changed, macOS treats this as a separate application.
Existing application permissions and preferences do not automatically migrate.
The package does not unregister or modify an existing upstream installation.

Run `python3 update.py --dry-run` to preview a pin update. `rebrand.py` applies
checked identity and updater changes after the Swift compatibility patch. Review
upstream branding, helper requirements, and update code on each source update.
Native macOS checks compile the app and run the helper self-test; launching the
GUI and verifying macOS permissions require a separate native smoke test.
