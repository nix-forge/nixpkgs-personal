"""Materialize only the selected pinned SWC carrier using its upstream verifier."""

import hashlib
import json
import os
import stat
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Pinned build tools use explicit argv, never a shell.
import sys
import tempfile
from pathlib import Path


def digest(path: Path) -> str:
    value = hashlib.sha512()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def main() -> None:
    node, verifier, select_script, native_package, target = sys.argv[1:]
    selected = json.loads(
        subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - Node is the declared immutable build input.
            [node, select_script, native_package],
            text=True,
        )
    )
    carrier = Path(selected["path"])
    build_root = Path(os.environ["NIX_BUILD_TOP"]).resolve(strict=True)
    if not carrier.is_relative_to(build_root):
        raise RuntimeError("selected SWC carrier is outside the owned build tree")
    info = carrier.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
        raise RuntimeError("selected SWC carrier must be an owned regular file")
    original = digest(carrier)
    with tempfile.TemporaryDirectory(
        prefix=".bookorbit-swc-", dir=carrier.parent
    ) as staging:
        raw = Path(staging) / "verified.node"
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Declared immutable verifier; owned build paths.
            [
                verifier,
                "--input",
                str(carrier),
                "--target",
                target,
                "--extract",
                str(raw),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"upstream SWC carrier verifier failed ({result.returncode}): "
                + result.stderr[-8192:]
            )
        receipt = json.loads(result.stdout)
        if receipt["kind"] != "carrier" or receipt["target"] != target:
            raise RuntimeError("unexpected upstream verifier result")
        if receipt["carrierSha512"] != original or digest(carrier) != original:
            raise RuntimeError("carrier identity changed during verification")
        if (
            receipt["rawSha512"] != digest(raw)
            or receipt["rawSize"] != raw.stat().st_size
        ):
            raise RuntimeError(
                "extracted payload does not match upstream verifier receipt"
            )
        # This additional readback preserves upstream SHA-512 and BLAKE3 checks.
        subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Same pinned verifier and checked source paths.
            [verifier, "--input", str(carrier), "--target", target, "--raw", str(raw)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        raw.chmod(stat.S_IMODE(info.st_mode))
        raw.replace(carrier)
    receipt["packageVersion"] = selected["version"]
    sys.stdout.write(
        "BOOKORBIT_SWC_MATERIALIZED " + json.dumps(receipt, sort_keys=True) + "\n"
    )
    sys.stdout.flush()


if __name__ == "__main__":
    main()
