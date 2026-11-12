"""Check real native desktopItems outputs against their application contracts."""

import argparse
import shlex

from check_desktop_entry import DesktopConfig


def main() -> None:
    """Validate generated metadata without building its target GUI application.

    Raises:
        ValueError: An entry differs from the package's advertised launcher.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entry")
    parser.add_argument("program")
    parser.add_argument("display_name")
    parser.add_argument("icon")
    args = parser.parse_args()
    config = DesktopConfig(interpolation=None)
    config.read(args.entry)
    entry = config["Desktop Entry"]
    expected = {
        "Type": "Application",
        "Name": args.display_name,
        "TryExec": args.program,
        "Icon": args.icon,
        "Terminal": "false",
        # This is the entry specification version, never the application release.
        "Version": "1.5",
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            raise ValueError(f"Unexpected {key} in {args.entry}: {entry.get(key)!r}")
    if shlex.split(entry["Exec"])[0] != args.program:
        raise ValueError("Exec must launch the advertised package command")


if __name__ == "__main__":
    main()
