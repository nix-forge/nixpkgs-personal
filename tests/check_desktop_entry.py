"""Check a desktop entry's installed command and icon after syntax validation."""

from __future__ import annotations

import argparse
import configparser
import os
import pathlib
import shlex
from typing import override


class DesktopConfig(configparser.ConfigParser):
    """Preserve the case-sensitive desktop entry keys."""

    @override
    def optionxform(self, optionstr: str) -> str:
        """Keep desktop key spelling unchanged.

        Returns:
            The unchanged key, preserving desktop entry case sensitivity.

        """
        return optionstr


def check_desktop(output: pathlib.Path, desktop_id: str, program_name: str) -> None:
    """Check artifact references in an application entry with a direct Exec command.

    Raises:
        ValueError: Metadata is invalid or a declared application artifact is missing.

    """
    entry = output / "share" / "applications" / desktop_id
    config = DesktopConfig(interpolation=None)
    with entry.open() as stream:
        config.read_file(stream)
    desktop = config["Desktop Entry"]
    if desktop.get("Type") != "Application" or not desktop.get("Name"):
        raise ValueError("Desktop entry must name an Application")
    # These recipes use direct commands and standalone field codes. General
    # desktop command-line syntax remains desktop-file-validate's responsibility.
    command = shlex.split(desktop["Exec"])[0]
    program = (
        pathlib.Path(command) if command.startswith("/") else output / "bin" / command
    )
    expected = output / "bin" / program_name
    if program != expected or not program.is_file() or not os.access(program, os.X_OK):
        raise ValueError(
            f"Desktop Exec does not select the installed command: {program}"
        )
    if "TryExec" in desktop and desktop["TryExec"] not in {program_name, str(expected)}:
        raise ValueError("Desktop TryExec does not select the installed command")
    icon = desktop.get("Icon", "")
    if not icon:
        raise ValueError("Desktop entry has no icon")
    if icon.startswith("/"):
        found = pathlib.Path(icon).is_file()
    else:
        found = any(
            path.is_file()
            for path in (output / "share" / "icons").glob(f"**/apps/{icon}.*")
        ) or any(
            (output / "share" / "pixmaps" / f"{icon}{extension}").is_file()
            for extension in ("", ".png", ".svg", ".xpm")
        )
    if not found:
        raise ValueError(f"Desktop entry icon is missing from the output: {icon}")


def main() -> None:
    """Check the installed desktop entry supplied by a recipe."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("desktop_id")
    parser.add_argument("program_name")
    args = parser.parse_args()
    check_desktop(args.output, args.desktop_id, args.program_name)


if __name__ == "__main__":
    main()
