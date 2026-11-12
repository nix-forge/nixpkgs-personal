"""Exercise stale and incomplete lifecycle decisions against independent inventories."""

from __future__ import annotations

import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "check_artcraft_patch_lifecycle",
    Path(__file__).with_name("check_artcraft_patch_lifecycle.py"),
)
assert SPEC is not None
assert SPEC.loader is not None
LIFECYCLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LIFECYCLE)


def inputs():
    registry = {
        "schemaVersion": 1,
        "packages": {
            "examplecraft": {
                "sourceRevision": "a" * 40,
                "patches": [
                    {
                        "file": "fix-recovery.patch",
                        "sha256": "b" * 64,
                        "kind": "upstream-backport",
                        "upstream": ["https://github.com/example/app/commit/123"],
                        "reason": "Preserve user backups on update failure.",
                        "removeWhen": "The selected source contains the accepted recovery fix.",
                    }
                ],
            },
            "craft-fonts": {"sourceRevision": "c" * 40, "patches": []},
        },
    }
    sources = [
        {"name": "examplecraft", "pins": {"rev": "a" * 40}},
        {"name": "craft-fonts", "pins": {"rev": "c" * 40}},
        {"name": "unrelated-package", "pins": {"version": "1.2.3"}},
    ]
    inventory = {"examplecraft": {"fix-recovery.patch": "b" * 64}, "craft-fonts": {}}
    return registry, sources, inventory


class PatchLifecycleTest(unittest.TestCase):
    def test_current_patch_and_zero_patch_package(self) -> None:
        self.assertEqual(LIFECYCLE.validate(*inputs()), 1)

    def test_stale_source_pin_requires_review_even_with_unchanged_patch(self) -> None:
        registry, sources, inventory = inputs()
        sources[0]["pins"]["rev"] = "d" * 40
        with self.assertRaisesRegex(ValueError, "Changed source revision"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_changed_patch_bytes_require_review_even_with_unchanged_pin(self) -> None:
        registry, sources, inventory = inputs()
        inventory["examplecraft"]["fix-recovery.patch"] = "e" * 64
        with self.assertRaisesRegex(ValueError, "Changed patch requires"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_added_actual_patch_cannot_escape_the_registry(self) -> None:
        registry, sources, inventory = inputs()
        inventory["examplecraft"]["new-workaround.patch"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "undocumented=.*new-workaround.patch"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_removed_actual_patch_leaves_an_orphan_decision(self) -> None:
        registry, sources, inventory = inputs()
        inventory["examplecraft"].clear()
        with self.assertRaisesRegex(ValueError, "orphaned=.*fix-recovery.patch"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_new_authoritative_app_requires_a_decision_even_without_patches(
        self,
    ) -> None:
        registry, sources, inventory = inputs()
        inventory["newcraft"] = {}
        sources.append({"name": "newcraft", "pins": {"rev": "d" * 40}})
        with self.assertRaisesRegex(ValueError, "undocumented=.*newcraft"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_removed_authoritative_app_leaves_an_orphan_package(self) -> None:
        registry, sources, inventory = inputs()
        del inventory["craft-fonts"]
        with self.assertRaisesRegex(ValueError, "orphaned=.*craft-fonts"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_missing_source_and_duplicate_source_entries_fail(self) -> None:
        registry, sources, inventory = inputs()
        with self.assertRaisesRegex(ValueError, "Missing source pin"):
            LIFECYCLE.validate(registry, sources[1:], inventory)
        with self.assertRaisesRegex(ValueError, "Duplicate source package"):
            LIFECYCLE.validate(registry, [*sources, sources[0]], inventory)

    def test_duplicate_patch_records_fail(self) -> None:
        registry, sources, inventory = inputs()
        patches = registry["packages"]["examplecraft"]["patches"]
        patches.append(copy.deepcopy(patches[0]))
        with self.assertRaisesRegex(ValueError, "Duplicate patch"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_path_traversal_and_absolute_patch_names_fail(self) -> None:
        for filename in [
            "../outside.patch",
            "/outside.patch",
            r"..\outside.patch",
            ".patch",
            "fix.txt",
        ]:
            registry, sources, inventory = inputs()
            registry["packages"]["examplecraft"]["patches"][0]["file"] = filename
            with (
                self.subTest(filename=filename),
                self.assertRaisesRegex(ValueError, "basename"),
            ):
                LIFECYCLE.validate(registry, sources, inventory)

    def test_unknown_kind_and_missing_rationale_fail(self) -> None:
        for field, value, error in [
            ("kind", "unreviewed", "Unknown patch kind"),
            ("reason", "  ", "reason must be nonempty"),
            ("removeWhen", "", "removal condition must be nonempty"),
        ]:
            registry, sources, inventory = inputs()
            registry["packages"]["examplecraft"]["patches"][0][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, error):
                LIFECYCLE.validate(registry, sources, inventory)

    def test_references_require_valid_public_https(self) -> None:
        for urls in [
            [],
            ["http://github.com/example/app"],
            ["https:///missing-host"],
            ["https://example.com/with space"],
            ["https://user:secret@example.com/path"],
            ["https://example.com:99999/path"],
            ["https://[broken"],
        ]:
            registry, sources, inventory = inputs()
            registry["packages"]["examplecraft"]["patches"][0]["upstream"] = urls
            with self.subTest(urls=urls), self.assertRaises(ValueError):
                LIFECYCLE.validate(registry, sources, inventory)

    def test_duplicate_json_keys_are_not_silently_overwritten(self) -> None:
        for text in [
            '{"packages": {}, "packages": {}}',
            '{"examplecraft": {"fix.patch": "a", "fix.patch": "b"}}',
        ]:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "input.json"
                path.write_text(text, encoding="utf-8")
                with (
                    self.subTest(text=text),
                    self.assertRaisesRegex(ValueError, "Duplicate JSON key"),
                ):
                    LIFECYCLE.load(path)

    def test_malformed_revision_hash_and_schema_fail(self) -> None:
        for value in [True, 2, "1"]:
            registry, sources, inventory = inputs()
            registry["schemaVersion"] = value
            with (
                self.subTest(schema=value),
                self.assertRaisesRegex(ValueError, "schemaVersion"),
            ):
                LIFECYCLE.validate(registry, sources, inventory)
        for field, value in [("sourceRevision", "main"), ("sourceRevision", "a" * 39)]:
            registry, sources, inventory = inputs()
            registry["packages"]["examplecraft"][field] = value
            with (
                self.subTest(revision=value),
                self.assertRaisesRegex(ValueError, "source revision"),
            ):
                LIFECYCLE.validate(registry, sources, inventory)
        registry, sources, inventory = inputs()
        registry["packages"]["examplecraft"]["patches"][0]["sha256"] = "b" * 63
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            LIFECYCLE.validate(registry, sources, inventory)

    def test_unknown_fields_cannot_hide_misspelled_policy(self) -> None:
        registry, sources, inventory = inputs()
        registry["packages"]["examplecraft"]["patches"][0]["remove_when"] = "typo"
        with self.assertRaisesRegex(ValueError, "missing or unknown fields"):
            LIFECYCLE.validate(registry, sources, inventory)


if __name__ == "__main__":
    unittest.main()
