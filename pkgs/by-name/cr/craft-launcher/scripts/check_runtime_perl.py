"""Check that the installed XML utility uses the host-platform Perl interpreter."""

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool", required=True, type=Path)
    parser.add_argument("--interpreter", required=True, type=Path)
    parser.add_argument("--elf-machine", required=True, type=int)
    parser.add_argument("--reject-tool", type=Path)
    args = parser.parse_args()
    if args.reject_tool is not None:
        with args.reject_tool.open("rb") as stream:
            original = stream.readline(4096).decode().strip().split()
        if original and original[0] == "#!" + str(args.interpreter):
            raise AssertionError(
                "The original cross utility no longer has the interpreter defect"
            )
    with args.tool.open("rb") as stream:
        shebang = stream.readline(4096).decode().strip().split()
    if not shebang or shebang[0] != "#!" + str(args.interpreter):
        raise AssertionError(f"Unexpected runtime interpreter: {shebang}")
    with args.interpreter.open("rb") as stream:
        header = stream.read(64)
    if (
        header[:6] != b"\x7fELF\x02\x01"
        or int.from_bytes(header[18:20], "little") != args.elf_machine
    ):
        raise AssertionError(
            "The runtime interpreter must be a host-platform ELF binary"
        )


if __name__ == "__main__":
    main()
