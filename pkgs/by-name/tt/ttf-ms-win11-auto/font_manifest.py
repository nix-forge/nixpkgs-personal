"""Inspect Windows font payloads without executing the OS installer."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ap/apple-fonts"))
# The CLI adds the sibling apple-fonts directory to sys.path at runtime.
from font_support import inventory  # ty: ignore[unresolved-import]


def extract(iso: Path, work: Path) -> Path:
    """Extract the font directory and license from a pinned evaluation ISO."""
    work.mkdir(parents=True, exist_ok=True)
    for args in [
        ["x", f"-o{work / 'iso'}", str(iso), "sources/install.wim"],
        [
            "e",
            f"-o{work / 'fonts'}",
            str(work / "iso/sources/install.wim"),
            "Windows/Fonts/*",
            "Windows/System32/Licenses/neutral/*/*/license.rtf",
        ],
    ]:
        subprocess.run(["7zz", *args, "-y"], check=True, stdout=subprocess.DEVNULL)
    if not (work / "fonts/license.rtf").is_file():
        raise ValueError("Missing Windows license.rtf")
    return work / "fonts"


def manifest(root: Path, version: str) -> dict:
    """Record file bytes and all named faces using the shared font inspector."""
    return {"version": version, "files": inventory(root)}


def validate(root: Path, expected: dict) -> None:
    """Reject missing, changed, renamed or additional font payloads."""
    if manifest(root, expected["version"]) != expected:
        raise ValueError("Windows font payload differs from the recorded inventory")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    expected = json.loads(args.manifest.read_text())
    validate(args.root, expected)


if __name__ == "__main__":
    main()
