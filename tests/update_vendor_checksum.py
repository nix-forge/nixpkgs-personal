"""Update the recorded checksum of one patched vendored Rust source file."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("crate", type=pathlib.Path)
    parser.add_argument("source_file")
    args = parser.parse_args()
    checksum_path = args.crate / ".cargo-checksum.json"
    checksum = json.loads(checksum_path.read_text())
    checksum["files"][args.source_file] = hashlib.sha256(
        (args.crate / args.source_file).read_bytes(),
    ).hexdigest()
    checksum_path.write_text(json.dumps(checksum))


if __name__ == "__main__":
    main()
