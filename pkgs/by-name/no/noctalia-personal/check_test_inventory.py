"""Require the pinned upstream suite, including private D-Bus integration cases."""

import argparse
import json
from pathlib import Path

REQUIRED = {
    "icon_resolver",
    "plugin_git_export",
    "upower_charge_limit_integration",
    "secret_collection_probe_integration",
    "tray_registration_default_integration",
    "tray_registration_ayatana_integration",
    "tray_registration_both_integration",
    "tray_discovery_default_integration",
    "tray_discovery_ayatana_integration",
    "tray_discovery_both_integration",
    "fingerprint_authenticator_integration",
    "bluetooth_connect_pass_integration",
    "notification_reply_integration",
    "bluetooth_property_integration",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    arguments = parser.parse_args()
    tests = json.loads(arguments.inventory.read_text())
    if not isinstance(tests, list) or any(not isinstance(test, dict) for test in tests):
        raise SystemExit("Meson did not return a test inventory")
    names = {test.get("name") for test in tests}
    missing = REQUIRED - names
    if missing or len(tests) < 176:
        raise SystemExit(
            f"Incomplete pinned suite: {len(tests)} cases; missing {sorted(missing)}"
        )
    print(
        f"Registered {len(tests)} upstream tests, including twelve private D-Bus tests"
    )


if __name__ == "__main__":
    main()
