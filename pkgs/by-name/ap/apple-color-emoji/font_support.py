"""Inspect this package's font identity without importing another package."""

import subprocess
from pathlib import Path


def faces(path: Path) -> list[str]:
    result = subprocess.run(
        ["fc-scan", "--format", "%{postscriptname}\n", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    # Fontconfig also emits an unnamed variable default for some named-instance fonts.
    names = sorted(set(filter(None, result.stdout.splitlines())))
    if not names:
        raise ValueError(f"No named font faces in {path}")
    return names
