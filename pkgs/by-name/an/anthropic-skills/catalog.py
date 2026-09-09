"""Validate the reviewed skill inventory and install a selected catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path


def fingerprint(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect(source: Path, root: str) -> dict:
    """Describe skill contents without guessing their licenses."""
    result = {}
    for skill in sorted((source / root).iterdir()):
        if not (skill / "SKILL.md").is_file():
            continue
        notices = {
            str(path.relative_to(skill)): fingerprint(path)
            for path in sorted(skill.rglob("*"))
            if path.is_file()
            and any(
                word in path.name.lower()
                for word in ("license", "notice", "copying", "ofl")
            )
        }
        result[skill.name] = {
            "skillHash": fingerprint(skill / "SKILL.md"),
            "notices": notices,
            "fonts": sorted(
                str(path.relative_to(skill))
                for path in skill.rglob("*")
                if path.suffix.lower() in {".ttf", ".otf", ".ttc", ".woff", ".woff2"}
            ),
        }
    return result


def validate(source: Path, manifest: dict) -> None:
    actual = inspect(source, manifest["root"])
    expected = {
        name: {key: item[key] for key in ("skillHash", "notices", "fonts")}
        for name, item in manifest["skills"].items()
    }
    if actual != expected:
        changed = sorted(
            name
            for name in actual.keys() | expected.keys()
            if actual.get(name) != expected.get(name)
        )
        raise ValueError("Skill/license review required: " + ", ".join(changed))
    root_notices = {
        path.name: fingerprint(path)
        for path in source.iterdir()
        if path.is_file()
        and any(
            word in path.name.lower()
            for word in ("license", "notice", "copying", "ofl")
        )
    }
    if root_notices != manifest["rootNotices"]:
        raise ValueError("Root notice review required")
    for name, digest in manifest["rootNotices"].items():
        if not (source / name).is_file() or fingerprint(source / name) != digest:
            raise ValueError(f"Root notice review required: {name}")


def install(source: Path, manifest: dict, names: list[str], output: Path) -> None:
    validate(source, manifest)
    if (
        not names
        or len(names) != len(set(names))
        or set(names) - manifest["skills"].keys()
    ):
        raise ValueError("Select a nonempty list of unique reviewed skill names")
    root = output / "share/agent-skills"
    root.mkdir(parents=True)
    for name in names:
        item = manifest["skills"][name]
        original = source / manifest["root"] / name
        target_name = f"{manifest['prefix']}-{name}"
        target = root / target_name
        shutil.copytree(original, target)
        if "unfree" not in item["licenses"]:
            path = target / "SKILL.md"
            text, count = re.subn(
                r"(?m)^name: .+$", f"name: {target_name}", path.read_text(), count=1
            )
            if count != 1:
                raise ValueError(f"Missing skill name: {name}")
            path.chmod(0o644)
            path.write_text(
                text
                + "\n<!-- Modified by nixpkgs-personal: namespace the skill name. -->\n"
            )
        else:
            # Namespace the enclosing directory only. Restricted contents stay
            # byte-identical, including their original SKILL.md name.
            if fingerprint(target / "SKILL.md") != item["skillHash"]:
                raise ValueError(f"Changed restricted skill: {name}")
    docs = output / "share/doc" / f"{manifest['prefix']}-skills"
    docs.mkdir(parents=True)
    for name in manifest["rootNotices"]:
        shutil.copyfile(source / name, docs / Path(name).name)
    selected = manifest | {"skills": {name: manifest["skills"][name] for name in names}}
    (docs / "installed-skills.json").write_text(json.dumps(selected, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "operation", choices=["inspect", "validate", "install", "verify"]
    )
    parser.add_argument("source", type=Path)
    parser.add_argument(
        "--manifest", type=Path, default=Path(__file__).with_name("catalog.json")
    )
    parser.add_argument("--selection", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if args.operation == "inspect":
        print(json.dumps(inspect(args.source, manifest["root"]), indent=2))
    elif args.operation == "validate":
        validate(args.source, manifest)
    else:
        if args.selection is None or args.output is None:
            parser.error("install requires --selection and --output")
        names = json.loads(args.selection.read_text())
        if args.operation == "install":
            install(args.source, manifest, names, args.output)
        else:
            verify(args.source, manifest, names, args.output)


def verify(source: Path, manifest: dict, names: list[str], output: Path) -> None:
    """Check selection, notice retention and unchanged restricted contents."""
    root = output / "share/agent-skills"
    expected = {f"{manifest['prefix']}-{name}" for name in names}
    if {path.name for path in root.iterdir()} != expected:
        raise ValueError("Installed selection differs from the requested skills")
    for name in names:
        item = manifest["skills"][name]
        target = root / f"{manifest['prefix']}-{name}"
        original = source / manifest["root"] / name
        for path in original.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(original)
            if str(relative) == "SKILL.md" and "unfree" not in item["licenses"]:
                continue
            if fingerprint(path) != fingerprint(target / relative):
                raise ValueError(f"Changed upstream content: {name}/{relative}")


if __name__ == "__main__":
    main()
