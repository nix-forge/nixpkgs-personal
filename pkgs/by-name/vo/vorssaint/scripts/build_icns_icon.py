"""Validate generated artifacts in an isolated build or VM fixture."""

import struct
import sys
from pathlib import Path

iconset = Path(sys.argv[1])
entries = {
    "ic11": "icon_16x16@2x.png",
    "ic12": "icon_32x32@2x.png",
    "ic07": "icon_128x128.png",
    "ic13": "icon_128x128@2x.png",
    "ic08": "icon_256x256.png",
    "ic14": "icon_256x256@2x.png",
    "ic09": "icon_512x512.png",
    "ic10": "icon_512x512@2x.png",
}
payload = b"".join(
    kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    for kind, filename in entries.items()
    for data in [(iconset / filename).read_bytes()]
)
Path(sys.argv[2]).write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
