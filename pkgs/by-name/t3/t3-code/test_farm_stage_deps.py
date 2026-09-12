"""Verify Node dependency resolution in the materialized staging tree."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "farm_stage_deps", Path(__file__).with_name("farm-stage-deps.py")
)
assert spec is not None and spec.loader is not None
farm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(farm)


class FarmTests(unittest.TestCase):
    def test_workspace_override_removal_is_reflected_in_staged_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            stage = root / "stage"
            stage.mkdir()
            (stage / "package.json").write_text(
                json.dumps({"dependencies": {"a": "1.0.0"}})
            )
            package = source / "node_modules/a"
            package.mkdir(parents=True)
            (package / "package.json").write_text(
                json.dumps({
                    "name": "a",
                    "version": "1.0.0",
                    "dependencies": {"removed": "1.0.0"},
                })
            )
            lockfile = source / "pnpm-lock.yaml"
            lockfile.write_text("lockfileVersion: '9.0'\nsnapshots:\n  a@1.0.0:\n")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(
                    farm._main([
                        "--source-root",
                        str(source),
                        "--stage",
                        str(stage),
                        "--lockfile",
                        str(lockfile),
                    ]),
                    0,
                )
            copied = json.loads((stage / "node_modules/a/package.json").read_text())
            self.assertEqual(copied["dependencies"], {})

    def test_nested_version_cycle_reuses_visible_ancestor(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            stage = root / "stage"
            stage.mkdir()
            (stage / "package.json").write_text(
                json.dumps({"dependencies": {"a": "1.0.0", "b": "1.0.0", "c": "1.0.0"}})
            )
            packages = [
                ("a", "1.0.0", {}),
                ("b", "1.0.0", {}),
                ("c", "1.0.0", {"a": "2.0.0"}),
                ("a", "2.0.0", {"b": "2.0.0"}),
                ("b", "2.0.0", {"a": "2.0.0"}),
            ]
            for name, version, dependencies in packages:
                directory = (
                    source
                    / "node_modules/.pnpm"
                    / f"{name}@{version}"
                    / "node_modules"
                    / name
                )
                directory.mkdir(parents=True)
                (directory / "package.json").write_text(
                    json.dumps({
                        "name": name,
                        "version": version,
                        "dependencies": dependencies,
                    })
                )
            lockfile = source / "pnpm-lock.yaml"
            lockfile.write_text("lockfileVersion: '9.0'\n")
            with contextlib.redirect_stdout(io.StringIO()):
                result = farm._main([
                    "--source-root",
                    str(source),
                    "--stage",
                    str(stage),
                    "--lockfile",
                    str(lockfile),
                ])
            self.assertEqual(result, 0)
            modules = stage / "node_modules"
            nested_b = modules / "c/node_modules/a/node_modules/b"
            self.assertEqual(farm._visible_version(nested_b, "a", modules), "2.0.0")
            self.assertFalse((nested_b / "node_modules/a").exists())
            self.assertEqual(len(list(modules.rglob("package.json"))), 5)


if __name__ == "__main__":
    unittest.main()
