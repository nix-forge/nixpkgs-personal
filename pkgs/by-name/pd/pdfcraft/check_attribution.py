"""Check that the mixed font input changes only its own attribution record."""

import sys
import tomllib
from pathlib import Path


def check(original: Path, patched: Path) -> None:
    """Preserve asset licences and declare the selected input's cumulative terms.

    Raises:
        ValueError: If unrelated asset terms change or the input loses Apache terms.

    """
    before = tomllib.loads((original / "ATTRIBUTION.toml").read_text())
    after = tomllib.loads((patched / "ATTRIBUTION.toml").read_text())
    if {key: value for key, value in before.items() if key != "build_input"} != {
        key: value for key, value in after.items() if key != "build_input"
    }:
        raise ValueError("A font build input must not change unrelated asset licences")
    inputs = {item["name"]: item for item in after["build_input"]}
    font_input = inputs["craft-fonts"]
    if font_input["licence"] != "OFL-1.1 AND Apache-2.0":
        raise ValueError("The Droid font requires cumulative Apache-2.0 terms")
    if "Droid" not in font_input["title"]:
        raise ValueError("Missing Droid font attribution")
    row = next(
        line
        for line in (patched / "ATTRIBUTION.md").read_text().splitlines()
        if line.startswith("| `craft-fonts`")
    )
    if " | OFL-1.1 AND Apache-2.0 | " not in row:
        raise ValueError("Generated Markdown disagrees with the source attribution")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]))
