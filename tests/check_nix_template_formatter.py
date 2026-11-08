"""Check native template formatting, unchanged timestamps and failed parses."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

from notification_process import run as run_command


def main(command: str) -> None:
    """Exercise the real formatter without tools from the caller's PATH.

    Raises:
        ValueError: Formatting changes an already formatted file or corrupts input.

    """
    with tempfile.TemporaryDirectory(prefix="template-formatter-") as temporary:
        source = Path(temporary) / "quoted template.nix.in"
        source.write_text('{name="@name@";}\n', encoding="utf-8")
        mode = 0o640
        source.chmod(mode)
        environment = os.environ | {"PATH": "/nonexistent"}
        run_command([command, str(source)], env=environment, check=True, timeout=30)
        formatted = source.read_bytes()
        if b'name = "@name@";' not in formatted:
            raise ValueError("The formatter did not format the Nix template")
        # A second run must leave both bytes and filesystem metadata unchanged.
        stamp = 1_600_000_000_000_000_000
        os.utime(source, ns=(stamp, stamp))
        run_command([command, str(source)], env=environment, check=True, timeout=30)
        if (
            source.read_bytes() != formatted
            or source.stat().st_mtime_ns != stamp
            or source.stat().st_mode & 0o777 != mode
        ):
            raise ValueError("The formatter rewrote an already formatted template")
        invalid = b"{ incomplete =\n"
        source.write_bytes(invalid)
        result = run_command(
            [command, str(source)],
            env=environment,
            check=False,
            capture_output=True,
            timeout=30,
        )
        if result.returncode == 0 or source.read_bytes() != invalid:
            raise ValueError("The formatter did not preserve an invalid template")
    print("Verified native template formatting, timestamps, modes and parse failures")


if __name__ == "__main__":
    main(sys.argv[1])
