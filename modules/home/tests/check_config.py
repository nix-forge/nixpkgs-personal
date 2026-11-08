"""Check the generated public module output without running a window manager."""

import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as source:
    config = tomllib.load(source)
if config["keys"]["Alt + C"] != {"switch_to_workspace": 0}:
    raise RuntimeError("The module changed the configured key command")
if config["settings"]["hot_reload"] is not True:
    raise RuntimeError("Hot reload default was not generated")
if config["settings"]["ui"]["mission_control"] != {
    "enabled": False,
    "window_previews": False,
}:
    raise RuntimeError("Capture-related features were not disabled by default")
