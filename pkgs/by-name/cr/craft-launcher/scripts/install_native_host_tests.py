"""Install the exact Cargo library-test executable from compiler artifacts."""

import argparse
import json
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact_log", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("target_name")
    args = parser.parse_args()
    executables = []
    for line in args.artifact_log.read_text().splitlines():
        artifact = json.loads(line)
        if (
            artifact.get("reason") == "compiler-artifact"
            and artifact.get("target", {}).get("name") == args.target_name
            and artifact.get("profile", {}).get("test")
            and artifact.get("executable")
        ):
            executables.append(Path(artifact["executable"]))
    if len(executables) != 1:
        raise SystemExit(
            f"Expected one {args.target_name} test executable, got {executables}"
        )
    if not executables[0].is_file():
        raise SystemExit(f"Missing test executable: {executables[0]}")
    shutil.copy2(executables[0], args.destination)


if __name__ == "__main__":
    main()
