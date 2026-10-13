"""Supply the SDK's SQLite headers without redefining its Clang module."""

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk", type=Path)
    parser.add_argument("headers", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    overlay = {
        "version": 0,
        "case-sensitive": "true",
        "use-external-names": False,
        "roots": [
            {
                "type": "file",
                "name": str(arguments.sdk / "usr/include" / header),
                "external-contents": str(arguments.headers / header),
            }
            for header in ("sqlite3.h", "sqlite3ext.h")
        ],
    }
    arguments.output.write_text(json.dumps(overlay), encoding="utf-8")


if __name__ == "__main__":
    main()
