"""Validate the font collection against its upstream manifest and notices."""

import hashlib
import sys
from pathlib import Path


def check(root: Path) -> None:
    """Reject missing, modified or unlicensed manifest entries.

    Raises:
        ValueError: If an entry escapes the source or fails metadata/hash validation.

    """
    root = root.resolve()
    entries = 0
    for line in (root / "fonts/manifest.txt").read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        family, style, filename, scripts, license_name, notice, checksum, url = (
            field.strip() for field in line.split(" | ")
        )
        font = (root / filename).resolve()
        license_file = (root / notice).resolve()
        if not font.is_relative_to(root) or not license_file.is_relative_to(root):
            raise ValueError(f"Manifest path escapes source: {filename}")
        if not all((family, style, scripts, url)) or license_name != "OFL-1.1":
            raise ValueError(f"Unexpected font metadata: {filename}")
        if hashlib.sha256(font.read_bytes()).hexdigest() != checksum:
            raise ValueError(f"Font checksum mismatch: {filename}")
        if "SIL OPEN FONT LICENSE" not in license_file.read_text():
            raise ValueError(f"Missing OFL license: {notice}")
        entries += 1
    if entries == 0:
        raise ValueError("Font collection is empty")


if __name__ == "__main__":
    check(Path(sys.argv[1]))
