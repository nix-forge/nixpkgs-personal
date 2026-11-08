"""Select the exact compiled PDF UI library test executable from Cargo JSON."""

import argparse
import json
import os
from pathlib import Path


def select_artifact(messages: Path) -> Path:
    """Require one executable UI library unit-test artifact.

    Returns:
        The native test executable path.

    Raises:
        RuntimeError: If Cargo did not produce the exact executable.

    """
    artifacts = []
    with messages.open(encoding="utf-8") as stream:
        for line in stream:
            item = json.loads(line)
            target = item.get("target", {})
            if (
                item.get("reason") == "compiler-artifact"
                and target.get("name") == "pdfcraft_ui_egui"
                and target.get("kind") == ["lib"]
                and item.get("profile", {}).get("test")
                and item.get("executable")
            ):
                artifacts.append(Path(item["executable"]))
    if (
        len(artifacts) != 1
        or not artifacts[0].is_file()
        or not os.access(artifacts[0], os.X_OK)
    ):
        raise RuntimeError(
            f"Expected one executable PDF UI libtest artifact, got {artifacts}"
        )
    return artifacts[0]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("messages", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(str(select_artifact(args.messages)), encoding="utf-8")
