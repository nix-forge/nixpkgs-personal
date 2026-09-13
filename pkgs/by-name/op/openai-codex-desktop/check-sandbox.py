"""Check packaged Codex sandbox enforcement on a native Linux host."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


def check(package: Path) -> None:
    """Run the bundled CLI without a user-installed bubblewrap on PATH."""
    bash = shutil.which("bash")
    true = shutil.which("true")
    if bash is None or true is None:
        raise RuntimeError("bash and coreutils must be installed")
    bash = str(Path(bash).resolve())
    coreutils = Path(true).resolve().parent
    if (coreutils / "bwrap").exists():
        raise RuntimeError("The test PATH must not supply bubblewrap")
    codex = package.resolve() / "lib/chatgpt/resources/codex"
    # :workspace also permits system temporary directories. Keep the outside
    # control in the user's home so it actually crosses the write boundary.
    with tempfile.TemporaryDirectory(
        prefix=".chatgpt-sandbox-check-", dir=Path.home()
    ) as temporary:
        root = Path(temporary).resolve()
        workspace = root / "workspace"
        workspace.mkdir()
        outside = root / "outside"
        outside.write_text("preserve\n", encoding="utf-8")
        command = [bash, "--noprofile", "--norc", "-c"]
        environment = {"PATH": str(coreutils)}

        def run(profile: str, script: str) -> None:
            result = subprocess.run(
                [
                    str(codex),
                    "sandbox",
                    "-P",
                    profile,
                    "-C",
                    str(workspace),
                    "--",
                    *command,
                    script,
                    "sandbox-check",
                    str(outside),
                ],
                env=environment,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    f"{profile} sandbox failed with {result.returncode}:\n"
                    f"{result.stdout}{result.stderr}"
                )

        run(
            ":workspace",
            'set -eu; printf "allowed\\n" > allowed; '
            'if printf "changed\\n" > "$1" 2>/dev/null; then exit 1; fi',
        )
        assert (workspace / "allowed").read_text(encoding="utf-8") == "allowed\n"
        assert outside.read_text(encoding="utf-8") == "preserve\n"
        run(
            ":read-only",
            "set -eu; test -r allowed; "
            'if printf "changed\\n" > allowed 2>/dev/null; then exit 1; fi',
        )
        assert (workspace / "allowed").read_text(encoding="utf-8") == "allowed\n"
    print("Workspace and read-only sandbox enforcement passed without bwrap on PATH")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "package", type=Path, help="Built openai-codex-desktop store path"
    )
    check(parser.parse_args().package)
