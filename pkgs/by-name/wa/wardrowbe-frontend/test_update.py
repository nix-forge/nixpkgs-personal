"""Check release selection, compatible fallback updates, and failure isolation."""

from __future__ import annotations

import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update
from packaging.specifiers import SpecifierSet
from packaging.version import Version

HASH = "sha256-" + "A" * 43 + "="
REV = "a" * 40
FALLBACKS = {
    "certifiVersion": "2026.10.23",
    "certifiHash": HASH,
    "cythonVersion": "3.3.0",
    "cythonHash": HASH,
    "sqlalchemyVersion": "2.1.4",
    "sqlalchemyHash": HASH,
    "arqVersion": "0.28.0",
    "arqHash": HASH,
    "redisVersion": "5.3.1",
    "redisHash": HASH,
}


def python_metadata(version, dependencies=()):
    return {
        "info": {
            "version": version,
            "requires_dist": list(dependencies),
            "requires_python": ">=3.9",
        },
        "urls": [
            {"packagetype": "sdist", "digests": {"sha256": "0" * 64}, "yanked": False}
        ],
    }


def pypi_fixture(responses):
    def fetch(name, version=None):
        metadata = responses[name]
        if version is not None:
            assert metadata["info"]["version"] == version
        return metadata

    return fetch


class UpdateTests(unittest.TestCase):
    def test_selects_semantic_latest_stable_application_release(self):
        releases = [
            {"tag_name": "wardrowbe-v1.9.0"},
            {"tag_name": "wardrowbe-v1.10.0"},
            {"tag_name": "wardrowbe-v2.0.0", "prerelease": True},
            {"tag_name": "wardrowbe-v3.0.0", "draft": True},
            {"tag_name": "frontend-v9.0.0"},
            {"tag_name": "v9.0.0"},
        ]
        with patch.object(update, "api", return_value=releases):
            self.assertEqual(
                update.github_release(None)["tag_name"], "wardrowbe-v1.10.0"
            )
        with (
            patch.object(update, "api", return_value=releases[-1]),
            self.assertRaisesRegex(ValueError, "stable Wardrowbe"),
        ):
            update.github_release("v9.0.0")

    def test_resolves_annotated_tag_to_commit(self):
        tag = "wardrowbe-v1.10.1"
        refs = f"{'b' * 40}\trefs/tags/{tag}\n{REV}\trefs/tags/{tag}^{{}}"
        with patch.object(update, "command", return_value=refs):
            self.assertEqual(update.tag_commit(tag), REV)

    def test_fallback_redis_respects_arq_bounds_and_yanked_sources(self):
        arq = python_metadata("0.28.0", ["redis[hiredis]>=4.2,<6", "click>=8"])
        with (
            patch.object(
                update,
                "pypi",
                side_effect=pypi_fixture({
                    "sqlalchemy": python_metadata("2.1.4", ["typing-extensions>=4"]),
                    "cython": python_metadata("3.3.0"),
                    "certifi": python_metadata("2026.10.23"),
                    "arq": arq,
                    "redis": python_metadata("5.3.1", ["PyJWT>=2.9"]),
                }),
            ),
            patch.object(update, "redis_versions", return_value=[Version("5.3.1")]),
        ):
            selected = update.fallback_sources()
            self.assertEqual(selected["redisVersion"], "5.3.1")
        with self.assertRaisesRegex(ValueError, "packaging review"):
            update.python_source(
                python_metadata("0.29.0", ["new-library>=1"]), {"redis", "click"}
            )

    def test_both_actual_updaters_render_required_compiler_fields(self):
        updaters = [update]
        sibling = Path(__file__).parent.parent / "wardrowbe-backend/update.py"
        if sibling.is_file():
            spec = importlib.util.spec_from_file_location(
                "backend_updater_compiler_fixture", sibling
            )
            if spec is None or spec.loader is None:
                raise RuntimeError("actual backend updater fixture cannot be loaded")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            updaters.append(module)
        for updater in updaters:
            with (
                self.subTest(updater=updater.PACKAGE.name),
                patch.object(
                    updater,
                    "pypi",
                    side_effect=pypi_fixture({
                        "sqlalchemy": python_metadata(
                            "2.1.4", ["typing-extensions>=4"]
                        ),
                        "cython": python_metadata("3.3.0"),
                        "certifi": python_metadata("2026.10.23"),
                        "arq": python_metadata("0.28.0", ["redis>=4,<6", "click>=8"]),
                        "redis": python_metadata("5.3.1", ["PyJWT>=2.9"]),
                    }),
                ),
                patch.object(
                    updater, "redis_versions", return_value=[Version("5.3.1")]
                ),
            ):
                dependencies = updater.fallback_sources()
                rendered = updater.render("1.11.0", REV, HASH, HASH, dependencies)
                self.assertEqual(updater.field(rendered, "cythonVersion"), "3.3.0")
                self.assertEqual(updater.field(rendered, "cythonHash"), HASH)
                self.assertEqual(updater.field(rendered, "sqlalchemyVersion"), "2.1.4")
                self.assertEqual(
                    updater.field(rendered, "certifiVersion"), "2026.10.23"
                )
                self.assertEqual(updater.field(rendered, "certifiHash"), HASH)

    def test_new_compiler_runtime_dependency_requires_review(self):
        with self.assertRaisesRegex(ValueError, "packaging review"):
            update.python_source(python_metadata("3.3.0", ["new-runtime>=1"]), set())

    def test_missing_redis_requirement_has_actionable_failure(self):
        with (
            patch.object(
                update,
                "pypi",
                side_effect=pypi_fixture({
                    "sqlalchemy": python_metadata("2.1.4", ["typing-extensions>=4"]),
                    "cython": python_metadata("3.3.0"),
                    "certifi": python_metadata("2026.10.23"),
                    "arq": python_metadata("0.28.0", ["click>=8"]),
                }),
            ),
            self.assertRaisesRegex(ValueError, "exactly one Redis requirement"),
        ):
            update.fallback_sources()

    def test_index_filters_yanked_incompatible_and_unstable_sources(self):
        index = {
            "files": [
                {"filename": "redis-5.3.1.tar.gz", "yanked": False},
                {"filename": "redis-5.9.0.tar.gz", "yanked": "broken release"},
                {"filename": "redis-8.0.0.tar.gz", "yanked": False},
                {"filename": "redis-5.9.1rc1.tar.gz", "yanked": False},
                {"filename": "redis-5.3.1-py3-none-any.whl", "yanked": False},
            ]
        }
        with patch.object(
            update.urllib.request,
            "urlopen",
            return_value=io.BytesIO(json.dumps(index).encode()),
        ):
            self.assertEqual(
                update.redis_versions(SpecifierSet(">=4.2,<6")),
                [Version("5.3.1")],
            )

    def test_failed_write_rolls_back_both_manifests(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first.nix"
            second = Path(temporary) / "second.nix"
            first.write_text("first")
            second.write_text("second")
            replace = Path.replace

            def fail_second(source, destination):
                if destination == second:
                    raise OSError("write failed")
                return replace(source, destination)

            with (
                patch.object(Path, "replace", fail_second),
                self.assertRaisesRegex(OSError, "write failed"),
            ):
                update.commit_sources({first: "updated", second: "updated"})
            self.assertEqual(first.read_text(), "first")
            self.assertEqual(second.read_text(), "second")
            self.assertEqual(
                sorted(p.name for p in Path(temporary).iterdir()),
                ["first.nix", "second.nix"],
            )

    def run_update(self, args, *, npm_failure=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            targets = [root / "wardrowbe-backend", root / "wardrowbe-frontend"]
            original = update.render("1.0.0", REV, HASH, HASH, FALLBACKS)
            for target in targets:
                target.mkdir()
                (target / "source.nix").write_text(original)

            def command(*argv, **_kwargs):
                if argv[0] == "nix":
                    return json.dumps({"storePath": temporary, "hash": HASH})
                if npm_failure:
                    raise RuntimeError("npm fetch failed")
                return HASH

            with (
                patch.object(update, "PACKAGE", targets[0]),
                patch.object(
                    update,
                    "github_release",
                    return_value={"tag_name": "wardrowbe-v1.1.0"},
                ),
                patch.object(update, "fallback_sources", return_value=FALLBACKS),
                patch.object(update, "tag_commit", return_value=REV),
                patch.object(update, "validate_source"),
                patch.object(update, "command", side_effect=command),
            ):
                if npm_failure:
                    with self.assertRaisesRegex(RuntimeError, "npm fetch failed"):
                        update.main(args)
                else:
                    self.assertEqual(update.main(args), 0)
            contents = [(target / "source.nix").read_text() for target in targets]
            if npm_failure or "--dry-run" in args:
                self.assertEqual(contents, [original, original])
            else:
                self.assertEqual(update.field(contents[0], "version"), "1.1.0")
                if "--paired" in args:
                    self.assertEqual(contents[0], contents[1])
                    for content in contents:
                        self.assertEqual(
                            update.field(content, "cythonVersion"), "3.3.0"
                        )
                        self.assertEqual(update.field(content, "cythonHash"), HASH)
                        self.assertEqual(
                            update.field(content, "sqlalchemyVersion"), "2.1.4"
                        )
                else:
                    self.assertEqual(contents[1], original)

    def test_failed_npm_fetch_does_not_change_either_package(self):
        self.run_update([], npm_failure=True)

    def test_preview_does_not_write(self):
        self.run_update(["--dry-run"])

    def test_update_synchronizes_pair_when_requested(self):
        self.run_update(["--paired"])

    def test_default_update_does_not_write_sibling_package(self):
        self.run_update([])

    def test_patch_failure_stops_update(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in (
                "LICENSE",
                "backend/requirements.txt",
                "backend/app/main.py",
                "backend/migrations/env.py",
            ):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            (root / "frontend").mkdir()
            (root / "frontend/package.json").write_text(
                json.dumps({"name": "app", "scripts": {"build": "next build"}})
            )
            (root / "frontend/package-lock.json").write_text(
                json.dumps({"name": "app", "packages": {"": {"version": "1.2.0"}}})
            )
            (root / "compatibility.patch").touch()
            (root / "package.nix").write_text(
                "{ patches = [ ./compatibility.patch ]; }"
            )
            with (
                patch.object(
                    update,
                    "command",
                    side_effect=RuntimeError("patch no longer applies"),
                ),
                self.assertRaisesRegex(RuntimeError, "patch no longer applies"),
            ):
                update.validate_source(root, [root])

    def test_patch_order_matches_recipe_and_dependencies_apply(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "source"
            root.mkdir()
            for name in (
                "LICENSE",
                "backend/requirements.txt",
                "backend/app/main.py",
                "backend/migrations/env.py",
            ):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            (root / "frontend").mkdir()
            (root / "frontend/package.json").write_text(
                json.dumps({"name": "app", "scripts": {"build": "next build"}})
            )
            (root / "frontend/package-lock.json").write_text(
                json.dumps({"name": "app", "packages": {"": {}}})
            )
            (root / "sample.txt").write_text("original\n")
            target = Path(temporary) / "wardrowbe-backend"
            target.mkdir()
            (target / "package.nix").write_text(
                "{ patches = [ ./z-first.patch ./a-second.patch ]; }"
            )
            (target / "z-first.patch").write_text(
                "--- a/sample.txt\n+++ b/sample.txt\n@@ -1 +1 @@\n-original\n+first\n"
            )
            (target / "a-second.patch").write_text(
                "--- a/sample.txt\n+++ b/sample.txt\n@@ -1 +1 @@\n-first\n+second\n"
            )
            update.validate_source(root, [target])
            self.assertEqual((root / "sample.txt").read_text(), "original\n")
            (target / "package.nix").write_text(
                "{ patches = [ ./a-second.patch ./z-first.patch ]; }"
            )
            with self.assertRaises(RuntimeError):
                update.validate_source(root, [target])

    def test_patch_list_rejects_missing_duplicate_and_undeclared_patches(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary)
            (target / "one.patch").touch()
            recipe = target / "package.nix"
            for expression in (
                "./missing.patch",
                "./one.patch ./one.patch",
                "",
                "fetchpatch {}",
            ):
                recipe.write_text("{ patches = [ " + expression + " ]; }")
                with self.assertRaises(ValueError):
                    update.package_patches(target)
            recipe.write_text("{ patches = [ ./one.patch ]; }")
            self.assertEqual(
                update.package_patches(target), [(target / "one.patch").resolve()]
            )

    def test_copied_package_updates_independently(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "package"
            root.mkdir()
            self.assertEqual(update.packages(root), [root])

    def test_duplicate_updaters_stay_identical(self):
        peer = update.PACKAGE.with_name("wardrowbe-backend") / "update.py"
        if peer.is_file():
            self.assertEqual(
                peer.read_bytes(), (update.PACKAGE / "update.py").read_bytes()
            )


if __name__ == "__main__":
    unittest.main()
