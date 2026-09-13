"""Exercise runtime module resolution across staged pnpm peer contexts."""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

SPEC = importlib.util.spec_from_file_location(
    "stage_deps", Path(__file__).with_name("farm-stage-deps.py")
)
assert SPEC is not None
assert SPEC.loader is not None
farm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(farm)


class StageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.target = self.root / "stage"
        self.target.mkdir()
        self.store = self.source / "node_modules/.pnpm"
        self.store.mkdir(parents=True)
        self.lock: dict = {
            "lockfileVersion": "9.0",
            "settings": {"autoInstallPeers": True, "excludeLinksFromLockfile": False},
            "importers": {"apps/desktop": {"dependencies": {}}},
            "packages": {},
            "snapshots": {},
        }
        (self.source / "node_modules/.modules.yaml").write_text(
            yaml.safe_dump({
                "layoutVersion": 5,
                "packageManager": "pnpm@10.34.4",
                "virtualStoreDir": ".pnpm",
                "storeDir": str(self.root / "unused-store"),
                "included": {
                    "dependencies": True,
                    "devDependencies": True,
                    "optionalDependencies": True,
                },
            })
        )
        self.seeds: dict[str, str] = {}

    def package(self, name: str, ref: str, code: str = "", **extra: object) -> Path:
        path = (
            self.store
            / (name.replace("/", "+") + "@" + ref.replace("(", "_").replace(")", ""))
            / "node_modules"
            / name
        )
        path.mkdir(parents=True)
        (path / "package.json").write_text(
            json.dumps({
                "name": name,
                "version": ref.split("(", maxsplit=1)[0],
                "main": "index.js",
                **extra,
            })
        )
        (path / "index.js").write_text(code)
        self.lock["snapshots"][f"{name}@{ref}"] = {}
        self.lock["packages"][f"{name}@{ref.split('(', maxsplit=1)[0]}"] = {
            "resolution": {"integrity": "sha512-AA=="}
        }
        return path

    def edge(
        self, parent: Path, child: Path, ref: str, *, optional: bool = False
    ) -> None:
        name = farm.manifest(child)["name"]
        parent_name = farm.manifest(parent)["name"]
        context = next(
            key
            for key in self.lock["snapshots"]
            if key.startswith(parent_name + "@")
            and parent.parent.parent.name
            == key.replace("(", "_").replace(")", "").replace("/", "+")
        )
        section = "optionalDependencies" if optional else "dependencies"
        self.lock["snapshots"][context].setdefault(section, {})[name] = ref
        farm.link(child, parent.parent / name)

    def root_dependency(
        self, name: str, path: Path, ref: str, spec: str | None = None
    ) -> None:
        spec = spec or ref.split("(", maxsplit=1)[0]
        self.seeds[name] = spec
        self.lock["importers"]["apps/desktop"]["dependencies"][name] = {
            "specifier": spec,
            "version": ref,
        }
        farm.link(path, self.source / "apps/desktop/node_modules" / name)

    def run_stage(self) -> int:
        (self.target / "package.json").write_text(
            json.dumps({
                "name": "fixture",
                "version": "1.0.0",
                "dependencies": self.seeds,
            })
        )
        lockfile = self.source / "pnpm-lock.yaml"
        lockfile.write_text(yaml.safe_dump(self.lock))
        return farm.stage(self.source, self.target, lockfile)

    @unittest.skipUnless(
        shutil.which("node"), "Node.js is needed to check runtime resolution"
    )
    def test_peer_contexts_cycles_and_detached_runtime(self) -> None:
        a = self.package("a", "1.0.0", "module.exports = require('plugin');")
        b = self.package("b", "1.0.0", "module.exports = require('plugin');")
        peer1 = self.package("peer", "1.0.0", "module.exports = 1;")
        peer2 = self.package("peer", "2.0.0", "module.exports = 2;")
        p1 = self.package(
            "plugin", "1.0.0(peer@1.0.0)", "module.exports = require('peer');"
        )
        p2 = self.package(
            "plugin", "1.0.0(peer@2.0.0)", "module.exports = require('peer');"
        )
        self.edge(a, p1, "1.0.0(peer@1.0.0)")
        self.edge(b, p2, "1.0.0(peer@2.0.0)")
        self.edge(p1, peer1, "1.0.0")
        self.edge(p2, peer2, "2.0.0")
        self.edge(peer2, b, "1.0.0")
        self.root_dependency("a", a, "1.0.0")
        self.root_dependency("b", b, "1.0.0")
        self.assertEqual(self.run_stage(), 6)
        shutil.rmtree(self.source)
        result = subprocess.run(
            ["node", "-e", "console.log(JSON.stringify([require('a'), require('b')]))"],
            cwd=self.target,
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(json.loads(result.stdout), [1, 2])
        for path in self.target.rglob("*"):
            if path.is_symlink():
                self.assertFalse(path.readlink().is_absolute())
                self.assertTrue(path.resolve().is_relative_to(self.target))
        lock = farm.read_yaml(self.target / "node_modules/.pnpm/lock.yaml")
        self.assertEqual(set(lock["importers"]), {"."})

    def test_missing_required_dependency_fails(self) -> None:
        a = self.package("a", "1.0.0")
        self.lock["snapshots"]["a@1.0.0"] = {"dependencies": {"missing": "1.0.0"}}
        self.root_dependency("a", a, "1.0.0")
        with self.assertRaisesRegex(ValueError, "missing required missing"):
            self.run_stage()

    def test_optional_platform_dependency_is_skipped(self) -> None:
        a = self.package("a", "1.0.0")
        mac = self.package("mac", "1.0.0", os=["darwin"])
        self.edge(a, mac, "1.0.0", optional=True)
        self.root_dependency("a", a, "1.0.0")
        self.assertEqual(self.run_stage(), 1)

    def test_workspace_override_removal_is_preserved(self) -> None:
        a = self.package("a", "1.0.0", dependencies={"removed": "1.0.0"})
        self.root_dependency("a", a, "1.0.0", "^1.0.0")
        self.assertEqual(self.run_stage(), 1)
        self.assertFalse((self.target / "node_modules/removed").exists())

    def test_promoted_incompatible_optional_seed_is_skipped(self) -> None:
        a = self.package("a", "1.0.0")
        self.package("native-musl", "1.0.0", libc=["musl"])
        self.lock["snapshots"]["native-musl@1.0.0"]["optional"] = True
        self.lock["packages"]["native-musl@1.0.0"]["libc"] = ["musl"]
        self.root_dependency("a", a, "1.0.0")
        self.seeds["native-musl"] = "1.0.0"
        self.assertEqual(self.run_stage(), 1)

    def test_installed_version_must_match_lock(self) -> None:
        a = self.package("a", "2.0.0")
        self.root_dependency("a", a, "1.0.0")
        with self.assertRaisesRegex(ValueError, "installed version differs"):
            self.run_stage()

    @unittest.skipUnless(
        shutil.which("pnpm"), "pnpm is needed to check the package collector"
    )
    def test_pnpm_lists_staged_transitive_closure(self) -> None:
        a = self.package("a", "1.0.0")
        b = self.package("b", "2.0.0")
        self.edge(a, b, "2.0.0")
        self.root_dependency("a", a, "1.0.0")
        self.run_stage()
        result = subprocess.run(
            ["pnpm", "list", "--prod", "--json", "--depth", "Infinity"],
            cwd=self.target,
            text=True,
            capture_output=True,
            check=True,
        )
        tree = json.loads(result.stdout)[0]["dependencies"]["a"]
        self.assertEqual(tree["dependencies"]["b"]["version"], "2.0.0")
        self.assertTrue(
            Path(tree["dependencies"]["b"]["path"]).is_relative_to(self.target)
        )

    def test_ambiguous_seed_context_is_rejected(self) -> None:
        self.package("plugin", "1.0.0(peer@1.0.0)")
        self.package("plugin", "1.0.0(peer@2.0.0)")
        self.seeds["plugin"] = "1.0.0"
        with self.assertRaisesRegex(ValueError, "unambiguously resolve"):
            self.run_stage()


if __name__ == "__main__":
    unittest.main()
