"""Extract the installed viewer JavaScript for its native syntax check."""

import sys
import zipfile
from pathlib import Path

with zipfile.ZipFile(sys.argv[1]) as archive:
    Path(sys.argv[3]).write_bytes(archive.read(sys.argv[2]))
