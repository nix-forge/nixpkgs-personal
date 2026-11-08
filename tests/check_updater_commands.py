"""Exercise packaged updater commands against editable standalone copies."""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

from notification_process import run as run_command


def main(specification: Path) -> None:
    """Run every updater's help and exercise launcher arguments and native tools.

    Raises:
        ValueError: The launcher lost arguments, local imports or declared tools.

    """
    entries = json.loads(specification.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory(prefix="native-updater-check-") as temporary:
        root = Path(temporary)
        for entry in entries:
            package = root / entry["name"]
            shutil.copytree(entry["source"], package)
            environment = {
                key: value for key, value in os.environ.items() if key != "PYTHONPATH"
            }
            environment["PATH"] = "/nonexistent"
            run_command(
                [entry["command"], "--package-dir", str(package), "--help"],
                cwd=root,
                env=environment,
                check=True,
                capture_output=True,
                timeout=30,
            )
        # The real native launcher must execute editable code, preserving arguments
        # and making its Nixpkgs/tooling scope available with an empty caller PATH.
        fixture = root / "editable package"
        fixture.mkdir()
        (fixture / "package.nix").write_text("{}: {}\n")
        (fixture / "local_module.py").write_text('VALUE = "local import"\n')
        (fixture / "update.py").write_text(
            "import json, os, pathlib, shutil, sys\n"
            "from local_module import VALUE\n"
            "pathlib.Path(sys.argv[1]).write_text(json.dumps({\n"
            "'args': sys.argv[2:], 'module': VALUE,\n"
            "'nix': shutil.which('nix'),\n"
            "'scope': os.environ['NIXPKGS_UPDATE_SOURCE'],\n"
            "'cert': os.environ['SSL_CERT_FILE']}))\n"
        )
        report = root / "report.json"
        arguments = ["spaces and $dollars", "single'quote", 'double"quote', "new\nline"]
        environment = {
            key: value for key, value in os.environ.items() if key != "PYTHONPATH"
        }
        environment["PATH"] = "/nonexistent"
        run_command(
            [
                entries[0]["command"],
                "--package-dir",
                str(fixture),
                str(report),
                *arguments,
            ],
            cwd=root,
            env=environment,
            check=True,
            capture_output=True,
            timeout=30,
        )
        actual = json.loads(report.read_text(encoding="utf-8"))
        if actual["args"] != arguments or actual["module"] != "local import":
            raise ValueError(
                "Native updater did not preserve editable imports and arguments"
            )
        if (
            not actual["nix"]
            or not Path(actual["cert"]).is_file()
            or not (Path(actual["scope"]) / "default.nix").is_file()
        ):
            raise ValueError(
                "Native updater did not declare its Nix and certificate inputs"
            )
        # Upstream rewrites this separate path argument into its update worktree.
        # It must take precedence over cwd discovery of the original checkout.
        run_command(
            [
                entries[0]["command"],
                "--source-directory",
                str(fixture),
                str(report),
                *arguments,
            ],
            cwd=root,
            env=environment,
            check=True,
            capture_output=True,
            timeout=30,
        )
        if json.loads(report.read_text(encoding="utf-8"))["args"] != arguments:
            raise ValueError(
                "Native updater did not use the rewritten source-directory argument"
            )
    print(f"Checked {len(entries)} native, standalone updater commands")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
