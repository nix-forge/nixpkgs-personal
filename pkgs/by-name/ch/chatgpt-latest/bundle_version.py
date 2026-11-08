"""Read the signed bundle version without executing the application."""

import plistlib
import sys
from pathlib import Path

with Path(sys.argv[1]).open("rb") as stream:
    version = plistlib.load(stream)["CFBundleShortVersionString"]
print(version)  # ruff: ignore[print] - Version probe interface.
