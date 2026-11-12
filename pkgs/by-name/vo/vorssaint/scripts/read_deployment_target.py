"""Read the deployment target from the application's upstream property list."""

import pathlib
import plistlib
import re
import sys

info = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
minimum = info.get("LSMinimumSystemVersion")
if (
    not isinstance(minimum, str)
    or re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", minimum) is None
):
    raise ValueError(
        "The upstream plist must declare a numeric macOS deployment minimum"
    )
sys.stdout.write(minimum + "\n")
