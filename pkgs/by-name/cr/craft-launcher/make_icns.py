"""Store a 1024-pixel PNG in the standard ic10 ICNS resource."""

import pathlib
import struct
import sys

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_HEADER_SIZE = 24
IC10_DIMENSIONS = (1024, 1024)

png = pathlib.Path(sys.argv[1]).read_bytes()
if len(png) < PNG_HEADER_SIZE or png[:8] != PNG_SIGNATURE or png[12:16] != b"IHDR":
    message = "The icon input must have a PNG signature and IHDR header"
    raise ValueError(message)
if struct.unpack(">II", png[16:24]) != IC10_DIMENSIONS:
    message = "An ic10 icon resource requires a 1024-by-1024 PNG"
    raise ValueError(message)
chunk = b"ic10" + struct.pack(">I", len(png) + 8) + png
pathlib.Path(sys.argv[2]).write_bytes(
    b"icns" + struct.pack(">I", len(chunk) + 8) + chunk
)
