"""Verify Rift's authored identity and the standard application bundle contract."""

import pathlib
import plistlib
import sys

from check_app_bundle import check_bundle

app = pathlib.Path(sys.argv[1])
check_bundle(app, expected_version=sys.argv[2], authored=True)
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
if info["CFBundleIdentifier"] != "git.acsandmann.rift":
    raise ValueError("Rift's bundle identity differs from upstream")
if info.get("LSUIElement") is not True:
    raise ValueError("Rift must run as a menu-bar application")
