"""Check the downstream full-int buffer guard on an extracted GCC helper.

The fixture directly calls a private helper with negative values excluded by
its public callers. It checks defensive capacity and compiler diagnostics,
not a reachable public API truncation or the full libgomp build failure.
"""

import argparse
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path


def extract_function(source: str) -> str:
    prefix = re.search(r'^#define STR_OMP_DEV_PREFIX "[^"\n]+"$', source, re.MULTILINE)
    function = re.search(
        r"static const char \*\ngomp_get_uid_for_device[ \t]*\([^\n]+\)\n\{.*?\n\}",
        source,
        re.DOTALL,
    )
    if prefix is None or function is None:
        raise ValueError("The upstream device UID function changed")
    return prefix.group() + "\n" + function.group() + "\n"


def compile_fixture(
    root: Path, fixture: Path, compiler: str
) -> subprocess.CompletedProcess:
    (root / "upstream-device-uid.h").write_text(
        extract_function((root / "libgomp/target.c").read_text())
    )
    return subprocess.run(
        [
            compiler,
            "-std=gnu11",
            "-O2",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-UNDEBUG",
            "-U_FORTIFY_SOURCE",
            "-D_FORTIFY_SOURCE=2",
            "-I",
            str(root),
            str(fixture),
            "-o",
            str(root / "device-uid-test"),
        ],
        check=False,
        capture_output=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--patch", required=True, type=Path)
    parser.add_argument("--fixture", required=True, type=Path)
    parser.add_argument("--compiler", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="libgomp-uid-") as temporary:
        root = Path(temporary)
        baseline = root / "baseline"
        (baseline / "libgomp").mkdir(parents=True)
        with tarfile.open(args.source, "r|*") as archive:
            for member in archive:
                if member.name.endswith("/libgomp/target.c") and member.isfile():
                    stream = archive.extractfile(member)
                    if stream is None or member.size > 2 * 1024 * 1024:
                        raise ValueError("Unexpected upstream source input")
                    (baseline / "libgomp/target.c").write_bytes(stream.read())
                    break
            else:
                raise ValueError("GCC archive has no libgomp target source")
        patched = root / "patched"
        shutil.copytree(baseline, patched)
        subprocess.run(
            ["patch", "--batch", "--forward", "--fuzz=0", "-p1", "-d", str(patched)],
            input=args.patch.read_bytes(),
            check=True,
        )
        before = compile_fixture(baseline, args.fixture, args.compiler)
        if before.returncode:
            if b"format-truncation" not in before.stderr:
                raise RuntimeError(before.stderr.decode(errors="replace"))
        else:
            failure = subprocess.run(
                [str(baseline / "device-uid-test")], check=False, capture_output=True
            )
            if failure.returncode != 1 or b"UID mismatch" not in failure.stderr:
                raise AssertionError(
                    "The unchanged helper no longer distinguishes the full-int fixture"
                )
        after = compile_fixture(patched, args.fixture, args.compiler)
        if after.returncode:
            raise RuntimeError(after.stderr.decode(errors="replace"))
        subprocess.run([str(patched / "device-uid-test")], check=True)


if __name__ == "__main__":
    main()
