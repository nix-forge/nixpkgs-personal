"""Exercise native document creation, rendering, exports and a document round trip."""

from __future__ import annotations

import json
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed native package tools, checked args, no shell.
import sys
import xml.etree.ElementTree as ET  # ruff: ignore[suspicious-xml-etree-import] - trusted output of our synthetic fixture.
from pathlib import Path

from check_craft_assets import check_png


def run(cli: Path, *arguments: str) -> str:
    """Run a bounded native CLI command and return its UTF-8 output.

    Returns:
        The successful native command output.

    """
    return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - immutable executable and explicit argument list.
        [str(cli), *arguments], check=True, capture_output=True, text=True, timeout=60
    ).stdout


def check(package: Path, script: Path, version: str) -> None:
    """Verify formats using a synthetic multilingual source document.

    Raises:
        ValueError: A version, command, format or round-trip assertion fails.

    """
    cli = package / "bin/figcraft-cli"
    if run(cli, "--version").strip() != f"figcraft-cli {version}":
        raise ValueError("Unexpected CLI version")
    commands = json.loads(run(cli, "commands", "--json"))
    if not commands:
        raise ValueError("Empty command catalog")
    result = run(cli, "run", str(script), "--out", "document.figcraft")
    steps = [json.loads(line) for line in result.splitlines() if line.strip()]
    if len(steps) != 2 or not all(step.get("ok") is True for step in steps):
        raise ValueError("Document creation did not execute both commands")
    original = json.loads(run(cli, "info", "document.figcraft", "--json"))
    run(cli, "render", "document.figcraft", "-o", "rendered.png", "--no-system-fonts")
    check_png(Path("rendered.png"))
    run(cli, "export", "document.figcraft", "-o", "rendered.svg")
    if ET.parse("rendered.svg").getroot().tag != "{http://www.w3.org/2000/svg}svg":  # ruff: ignore[suspicious-xml-element-tree-usage] - our own bounded synthetic export.
        raise ValueError("Invalid SVG export")
    run(cli, "export", "document.figcraft", "-o", "rendered.pdf")
    if not Path("rendered.pdf").read_bytes().startswith(b"%PDF-"):
        raise ValueError("Invalid PDF export")
    run(cli, "export", "document.figcraft", "-o", "document.fig")
    imported = json.loads(run(cli, "info", "document.fig", "--json"))
    if not imported.get("pages"):
        raise ValueError("Exported .fig document could not be imported")
    run(cli, "convert", "document.figcraft", "document.json")
    run(cli, "convert", "document.json", "roundtrip.figcraft")
    restored = json.loads(run(cli, "info", "roundtrip.figcraft", "--json"))
    run(cli, "convert", "roundtrip.figcraft", "roundtrip.json")
    if json.loads(Path("document.json").read_text(encoding="utf-8")) != json.loads(
        Path("roundtrip.json").read_text(encoding="utf-8")
    ):
        raise ValueError("Native/JSON document round trip changed content fields")
    # The filename is presentation metadata; every document-content field must match.
    original.pop("file", None)
    restored.pop("file", None)
    if restored != original:
        raise ValueError("Native/JSON document round trip changed its contents")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
