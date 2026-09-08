"""Run package Python tests in separate processes to isolate local module names."""

import argparse
import subprocess
import sys
from pathlib import Path


def main(root: Path) -> None:
    suites = 0
    for package in sorted((root / "pkgs/by-name").glob("*/*")):
        if not list(package.glob("test_*.py")):
            continue
        print(f"Testing {package.name}", flush=True)
        subprocess.run(
            [
                sys.executable,
                "-B",
                "-m",
                "unittest",
                "discover",
                "-s",
                str(package),
                "-p",
                "test_*.py",
            ],
            check=True,
            timeout=120,
        )
        suites += 1
    if not suites:
        raise ValueError("No package test suites found")
    print(f"Passed {suites} package test suites")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    main(parser.parse_args().root.resolve())
