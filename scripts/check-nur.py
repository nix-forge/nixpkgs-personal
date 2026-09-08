#!/usr/bin/env python3
"""Run NUR's restricted index evaluation and our native-platform evaluation contract."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NUR_REVISION = "6e73a28249bbd53525bc1a7b385fcf3413c4e056"


def source_info(reference: str) -> dict[str, str]:
    """Fetch a source tree before entering restricted evaluation."""
    result = subprocess.run(
        ["nix", "flake", "prefetch", "--json", reference],
        timeout=180,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nixpkgs", choices=["locked", "unstable"], default="locked")
    parser.add_argument("--output", type=Path, default=Path("nur-results"))
    args = parser.parse_args()
    lock = json.loads((ROOT / "flake.lock").read_text())
    locked = lock["nodes"][lock["nodes"]["root"]["inputs"]["nixpkgs"]]["locked"]
    reference = (
        f"github:{locked['owner']}/{locked['repo']}/{locked['rev']}"
        if args.nixpkgs == "locked"
        else "github:NixOS/nixpkgs/nixos-unstable"
    )
    # Resolve moving branches once, then fetch that exact revision. Lazy-tree Nix
    # metadata may omit its store path and NAR hash until explicitly prefetched.
    metadata = json.loads(
        subprocess.run(
            ["nix", "flake", "metadata", "--json", "--no-write-lock-file", reference],
            timeout=180,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    resolved_reference = metadata["url"]
    nixpkgs_source = source_info(resolved_reference)
    expected_hash = locked.get("narHash") if args.nixpkgs == "locked" else None
    if expected_hash is not None and nixpkgs_source["hash"] != expected_hash:
        raise RuntimeError("Fetched Nixpkgs does not match flake.lock's NAR hash")
    nixpkgs = Path(nixpkgs_source["storePath"])
    nur = Path(source_info(f"github:nix-community/NUR/{NUR_REVISION}")["storePath"])
    evaluator = nur / "lib/evalRepo.nix"
    args.output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="nur-eval-") as directory:
        temp = Path(directory)
        arguments = temp / "args.json"
        arguments.write_text(json.dumps({"src": str(ROOT / "default.nix")}))
        wrapper = temp / "default.nix"
        # Paths become Nix strings via JSON encoding, never interpolated shell code.
        wrapper.write_text(
            "let pkgs = import <nixpkgs> {}; "
            f"args = builtins.fromJSON (builtins.readFile {json.dumps(str(arguments))}); "
            f"in import {json.dumps(str(evaluator))} {{ "
            'name = "nix-forge"; url = "https://github.com/nix-forge/nixpkgs-personal"; '
            "src = /. + args.src; inherit pkgs; inherit (pkgs) lib; }\n"
        )
        command = [
            "nix-env",
            "-f",
            str(wrapper),
            "-qa",
            "*",
            "--meta",
            "--xml",
            "--allowed-uris",
            "https://static.rust-lang.org",
            "--option",
            "restrict-eval",
            "true",
            "--option",
            "allow-import-from-derivation",
            "true",
            "--drv-path",
            "--show-trace",
            "-I",
            f"nixpkgs={nixpkgs}",
            "-I",
            str(ROOT),
            "-I",
            str(wrapper),
            "-I",
            str(arguments),
            "-I",
            str(evaluator),
        ]
        # Match NUR's policy, including no inherited allowUnfree or user config.
        with (args.output / "index.xml").open("w") as output:
            subprocess.run(
                command,
                check=True,
                text=True,
                stdout=output,
                timeout=180,
                env={
                    "PATH": os.environ["PATH"],
                    # Only the explicit -I sources belong in restricted evaluation.
                    "NIX_PATH": "",
                    "NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM": "1",
                },
            )
        count = len(ET.parse(args.output / "index.xml").getroot().findall("item"))
        if count == 0:
            raise RuntimeError("NUR evaluation returned no package entries")

    result = subprocess.run(
        [
            "nix-instantiate",
            "--eval",
            "--strict",
            "--json",
            "--show-trace",
            "--option",
            "allow-import-from-derivation",
            "false",
            str(ROOT / "tests/nur-supported.nix"),
            "--argstr",
            "nixpkgsPath",
            str(nixpkgs),
            "--argstr",
            "repositoryPath",
            str(ROOT),
        ],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    platforms = json.loads(result.stdout)
    summary = {
        "repository_revision": os.environ.get("GITHUB_SHA"),
        "nixpkgs_reference": reference,
        "nixpkgs_resolved_reference": resolved_reference,
        "nixpkgs_revision": metadata["locked"]["rev"],
        "nixpkgs_nar_hash": nixpkgs_source["hash"],
        "nixpkgs_store_path": str(nixpkgs),
        "nur_revision": NUR_REVISION,
        "indexed_packages": count,
        "supported_evaluations": {
            system: len(packages) for system, packages in platforms.items()
        },
        "builds_performed": False,
    }
    (args.output / "platforms.json").write_text(json.dumps(platforms, indent=2) + "\n")
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    if "GITHUB_STEP_SUMMARY" in os.environ:
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
            output.write(
                "### NUR compatibility\n\n```json\n"
                + json.dumps(summary, indent=2)
                + "\n```\n"
            )


if __name__ == "__main__":
    main()
