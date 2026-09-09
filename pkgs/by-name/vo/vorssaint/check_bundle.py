"""Check the installed unofficial app and its helper identity agree."""

import plistlib
import sys
from pathlib import Path


def check(output: Path) -> None:
    apps = list((output / "Applications").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Expected one application")
    contents = apps[0] / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    app_id = info["CFBundleIdentifier"]
    if app_id != "io.github.ianhollow.personalmonitor":
        raise ValueError("Unexpected application identity")
    if (
        info["CFBundleName"] != "PersonalMonitor"
        or info["CFBundleExecutable"] != "PersonalMonitor"
    ):
        raise ValueError("Unexpected application name")
    if not (contents / "MacOS" / info["CFBundleExecutable"]).is_file():
        raise ValueError("Missing application executable")
    helper = app_id + ".fan-control"
    daemon = plistlib.loads(
        (contents / "Library/LaunchDaemons" / f"{helper}.plist").read_bytes()
    )
    if daemon["Label"] != helper or helper not in daemon["MachServices"]:
        raise ValueError("Helper and application identifiers disagree")
    if not (apps[0] / daemon["BundleProgram"]).is_file():
        raise ValueError("Missing helper referenced by launchd")
    if not (output / "share/doc/vorssaint/TRADEMARKS.md").is_file():
        raise ValueError("Missing upstream branding policy")


if __name__ == "__main__":
    check(Path(sys.argv[1]))
