"""Test AudioMuse-AI update guards without network requests."""

from __future__ import annotations

import contextlib
import io
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update

SOURCE_PATH = Path(__file__).with_name("source.nix")
FAKE_HASH = "sha256-" + "A" * 43 + "="
FAKE_REVISION = "a" * 40


def _current_source() -> update._Source:
    return update._parse_existing(SOURCE_PATH.read_text(encoding="utf-8"))


def _common_requirements(
    *,
    google_genai: str = "1.57.0",
    transformers: str = "4.57.6",
    huggingface_hub: str = "0.36.2",
    mistralai: str = "1.12.4",
    tokenizers: str = "0.22.2",
) -> str:
    return (
        "google-genai==" + google_genai + "\n"
        "transformers=="
        + transformers
        + "\n"
        + "huggingface-hub=="
        + huggingface_hub
        + "\n"
        + "mistralai=="
        + mistralai
        + "\n"
        + "tokenizers=="
        + tokenizers
        + "\n"
    )


class ManifestTests(unittest.TestCase):
    def test_manifest_round_trips(self) -> None:
        content = SOURCE_PATH.read_text(encoding="utf-8")
        source = update._parse_existing(content)
        release = update._Release(source.app_version, source.app_tag, source.app_rev)
        self.assertEqual(
            update._render_source(source, release, source.app_hash), content
        )

    def test_render_updates_only_application_pin(self) -> None:
        source = _current_source()
        updated = update._render_source(
            source,
            update._Release("3.7.0", "v3.7.0", FAKE_REVISION),
            FAKE_HASH,
        )
        parsed = update._parse_existing(updated)
        self.assertEqual(parsed.app_version, "3.7.0")
        self.assertEqual(parsed.app_tag, "v3.7.0")
        self.assertEqual(parsed.app_rev, FAKE_REVISION)
        self.assertEqual(parsed.app_hash, FAKE_HASH)
        self.assertEqual(parsed.compatibility, source.compatibility)
        self.assertEqual(parsed.model_release, source.model_release)
        self.assertEqual(parsed.google_genai, source.google_genai)
        self.assertEqual(parsed.huggingface_hub, source.huggingface_hub)
        self.assertEqual(parsed.mistralai, source.mistralai)
        self.assertEqual(parsed.transformers, source.transformers)

    def test_parser_rejects_tag_revision_pins(self) -> None:
        content = SOURCE_PATH.read_text(encoding="utf-8").replace(
            'rev = "31239fa986afb91a15e039e1a9a64ed5a2d6fa12";',
            'rev = "v3.6.0";',
            1,
        )
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            update._parse_existing(content)


class DiscoveryTests(unittest.TestCase):
    def test_selection_ignores_model_and_prerelease_tags(self) -> None:
        release = update._select_release([
            {"draft": False, "prerelease": False, "tag_name": "v99.0.0-model"},
            {"draft": False, "prerelease": True, "tag_name": "v9.0.0"},
            {"draft": True, "prerelease": False, "tag_name": "v8.0.0"},
            {"draft": False, "prerelease": False, "tag_name": "v3.5.0"},
            {"draft": False, "prerelease": False, "tag_name": "v3.6.0"},
        ])
        self.assertEqual(release, update._Release("3.6.0", "v3.6.0"))

    def test_requirements_are_exact_and_unique(self) -> None:
        self.assertEqual(
            update._requirement_version(
                _common_requirements(), "huggingface-hub", label="common.txt"
            ),
            "0.36.2",
        )
        self.assertEqual(
            update._requirement_version(
                'onnxruntime==1.28.0; platform_system == "Linux"\n',
                "onnxruntime",
                label="linux.txt",
            ),
            "1.28.0",
        )

    def test_transformers_requirement_contains_the_reviewed_version(self) -> None:
        self.assertTrue(
            update._requirement_contains("tokenizers>=0.22.0,<=0.23.2", "0.23.2")
        )
        self.assertFalse(
            update._requirement_contains("tokenizers>=0.22.0,<=0.23.2", "0.23.3")
        )

    def test_version_comparison_ignores_trailing_zeroes(self) -> None:
        self.assertEqual(update._version_key("0.23"), update._version_key("0.23.0"))

    def test_transformers_setup_requirement_is_unique(self) -> None:
        with patch.object(
            update,
            "_fetch_text",
            return_value="""_deps = [\n    "tokenizers>=0.22.0,<=0.23.0",\n]\n""",
        ):
            self.assertEqual(
                update._fetch_transformers_tokenizers_requirement(FAKE_REVISION),
                "tokenizers>=0.22.0,<=0.23.0",
            )

    def test_managed_python_source_follows_release_requirement(self) -> None:
        source = _current_source()
        requirements = update._Requirements(
            google_genai="1.58.0",
            huggingface_hub="0.36.2",
            mistralai="1.12.4",
            transformers="4.57.6",
            tokenizers="0.22.2",
            onnxruntime="1.28.0",
        )
        replacement = update._PythonSource(
            "1.58.0", "v1.58.0", FAKE_REVISION, FAKE_HASH
        )
        with patch.object(update, "_fetch_python_source", return_value=replacement):
            updated = update._update_python_sources(source, requirements, refresh=False)
        self.assertEqual(updated[0], replacement)
        self.assertEqual(updated[1], source.huggingface_hub)
        self.assertEqual(updated[2], source.mistralai)
        self.assertEqual(updated[3], source.transformers)

    def test_transformers_source_refresh_checks_nixpkgs_tokenizers(self) -> None:
        source = _current_source()
        requirements = update._Requirements(
            google_genai="1.57.0",
            huggingface_hub="0.36.2",
            mistralai="1.12.4",
            transformers="4.57.7",
            tokenizers="0.22.2",
            onnxruntime="1.28.0",
        )
        replacement = update._PythonSource(
            "4.57.7", "v4.57.7", FAKE_REVISION, FAKE_HASH
        )
        with (
            patch.object(update, "_fetch_python_source", return_value=replacement),
            patch.object(
                update,
                "_fetch_transformers_tokenizers_requirement",
                return_value="tokenizers>=0.22.0,<=0.23.2",
            ),
            patch.object(update, "_nixpkgs_python_version", return_value="0.23.2"),
        ):
            updated = update._update_python_sources(source, requirements, refresh=False)
        self.assertEqual(updated[3].version, "4.57.7")
        self.assertEqual(
            updated[3].upstream_tokenizers_requirement,
            "tokenizers>=0.22.0,<=0.23.2",
        )
        self.assertEqual(
            updated[3].tokenizers_requirement,
            "tokenizers>=0.22.0,<=0.23.2",
        )

    def test_duplicate_requirement_pin_is_rejected(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            update._requirement_version(
                "tokenizers==0.22.2\ntokenizers==0.23.0\n",
                "tokenizers",
                label="common.txt",
            )


class ContractTests(unittest.TestCase):
    def test_current_upstream_contract_is_accepted(self) -> None:
        source = _current_source()
        tree_paths = set(update.REQUIRED_SOURCE_ENTRIES)
        source_tree = {
            "truncated": False,
            "tree": [
                {
                    "path": path,
                    "type": update.REQUIRED_SOURCE_ENTRIES[path],
                }
                for path in tree_paths
            ],
        }
        files = {
            "requirements/common.txt": _common_requirements(),
            "requirements/linux.txt": "onnxruntime==1.28.0\n",
            "service_roles.py": "\n".join(update.SERVICE_PATCH_ANCHORS),
            "Dockerfile": (
                "https://github.com/NeptuneHub/AudioMuse-AI/releases/download/"
                "v5.0.0-model/model.onnx\n"
                "https://github.com/NeptuneHub/AudioMuse-AI-DCLAP/releases/download/"
                "v1/model.onnx\n"
                "https://github.com/NeptuneHub/AudioMuse-AI-SAE/releases/download/"
                "v1/model.onnx\n"
            ),
            "Dockerfile-noavx2": (
                "https://github.com/NeptuneHub/AudioMuse-AI/releases/download/"
                "v5.0.0-model/model.onnx\n"
                "https://github.com/NeptuneHub/AudioMuse-AI-DCLAP/releases/download/"
                "v1/model.onnx\n"
            ),
        }

        def fetch(url: str, *, label: str) -> str:
            return files[url.split(f"/{FAKE_REVISION}/", 1)[1]]

        with (
            patch.object(update, "_fetch_json", return_value=source_tree),
            patch.object(update, "_fetch_text", side_effect=fetch),
        ):
            requirements = update._validate_release_contract(source, FAKE_REVISION)
        self.assertEqual(requirements.google_genai, "1.57.0")
        self.assertEqual(requirements.mistralai, "1.12.4")

    def test_required_source_layout_is_rejected(self) -> None:
        tree = {
            "truncated": False,
            "tree": [{"path": "LICENSE", "type": "blob"}],
        }
        with (
            patch.object(update, "_fetch_json", return_value=tree),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            update._validate_source_layout(FAKE_REVISION)

    def test_managed_requirement_changes_are_returned_for_source_updates(self) -> None:
        source = _current_source()
        with (
            patch.object(
                update,
                "_fetch_text",
                side_effect=[
                    _common_requirements(transformers="4.57.7"),
                    "onnxruntime==1.28.0\n",
                ],
            ),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            requirements = update._validate_requirements(source, FAKE_REVISION)
        self.assertEqual(requirements.transformers, "4.57.7")

    def test_nixpkgs_backed_requirement_changes_are_rejected(self) -> None:
        source = _current_source()
        with (
            patch.object(
                update,
                "_fetch_text",
                side_effect=[
                    _common_requirements(tokenizers="0.23.0"),
                    "onnxruntime==1.28.0\n",
                ],
            ),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            update._validate_requirements(source, FAKE_REVISION)

    def test_changed_model_release_is_rejected(self) -> None:
        source = _current_source()
        changed = (
            "https://github.com/NeptuneHub/AudioMuse-AI/releases/download/"
            "v6.0.0-model/model.onnx\n"
            "https://github.com/NeptuneHub/AudioMuse-AI-DCLAP/releases/download/"
            "v1/model.onnx\n"
            "https://github.com/NeptuneHub/AudioMuse-AI-SAE/releases/download/"
            "v1/model.onnx\n"
        )
        with (
            patch.object(update, "_fetch_text", return_value=changed),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            update._validate_model_references(source, FAKE_REVISION)

    def test_missing_model_reference_in_one_dockerfile_is_rejected(self) -> None:
        source = _current_source()
        complete = (
            "https://github.com/NeptuneHub/AudioMuse-AI/releases/download/"
            "v5.0.0-model/model.onnx\n"
            "https://github.com/NeptuneHub/AudioMuse-AI-DCLAP/releases/download/"
            "v1/model.onnx\n"
            "https://github.com/NeptuneHub/AudioMuse-AI-SAE/releases/download/"
            "v1/model.onnx\n"
        )
        noavx2_missing = complete.replace(
            "https://github.com/NeptuneHub/AudioMuse-AI-SAE/releases/download/"
            "v1/model.onnx\n",
            "",
        ).replace(
            "https://github.com/NeptuneHub/AudioMuse-AI-DCLAP/releases/download/"
            "v1/model.onnx\n",
            "",
        )
        with (
            patch.object(update, "_fetch_text", side_effect=[complete, noavx2_missing]),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            update._validate_model_references(source, FAKE_REVISION)


class MainTests(unittest.TestCase):
    def test_python_pin_update_writes_without_rehashing_application_source(
        self,
    ) -> None:
        source_content = SOURCE_PATH.read_text(encoding="utf-8")
        source = _current_source()
        replacement = update._PythonSource(
            "1.58.0", "v1.58.0", FAKE_REVISION, FAKE_HASH
        )
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source_path = directory / "source.nix"
            source_path.write_text(source_content, encoding="utf-8")
            script_path = directory / "update.py"
            release = update._Release(
                source.app_version, source.app_tag, source.app_rev
            )
            with (
                patch.object(update, "__file__", str(script_path)),
                patch.object(update, "_discover_release", return_value=release),
                patch.object(update, "_resolve_revision", return_value=source.app_rev),
                patch.object(
                    update,
                    "_validate_release_contract",
                    return_value=update._Requirements(
                        google_genai="1.58.0",
                        huggingface_hub="0.36.2",
                        mistralai="1.12.4",
                        transformers="4.57.6",
                        tokenizers="0.22.2",
                        onnxruntime="1.28.0",
                    ),
                ),
                patch.object(
                    update,
                    "_update_python_sources",
                    return_value=(
                        replacement,
                        source.huggingface_hub,
                        source.mistralai,
                        source.transformers,
                    ),
                ),
                patch.object(update, "_prefetch_source_hash") as prefetch,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(update._main([]), 0)

            updated = update._parse_existing(source_path.read_text(encoding="utf-8"))
            self.assertEqual(updated.google_genai, replacement)
            self.assertEqual(updated.app_hash, source.app_hash)
            prefetch.assert_not_called()

    def test_dry_run_does_not_write_and_successful_update_is_atomic(self) -> None:
        source_content = SOURCE_PATH.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source_path = directory / "source.nix"
            source_path.write_text(source_content, encoding="utf-8")
            source_path.chmod(0o640)
            script_path = directory / "update.py"
            release = update._Release("3.7.0", "v3.7.0")
            with (
                patch.object(update, "__file__", str(script_path)),
                patch.object(update, "_discover_release", return_value=release),
                patch.object(update, "_resolve_revision", return_value=FAKE_REVISION),
                patch.object(
                    update,
                    "_validate_release_contract",
                    return_value=update._Requirements(
                        google_genai="1.57.0",
                        huggingface_hub="0.36.2",
                        mistralai="1.12.4",
                        transformers="4.57.6",
                        tokenizers="0.22.2",
                        onnxruntime="1.28.0",
                    ),
                ),
                patch.object(
                    update,
                    "_update_python_sources",
                    return_value=(
                        _current_source().google_genai,
                        _current_source().huggingface_hub,
                        _current_source().mistralai,
                        _current_source().transformers,
                    ),
                ),
                patch.object(update, "_prefetch_source_hash", return_value=FAKE_HASH),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(update._main(["--dry-run"]), 0)
                self.assertEqual(
                    source_path.read_text(encoding="utf-8"), source_content
                )
                self.assertEqual(update._main([]), 0)

            parsed = update._parse_existing(source_path.read_text(encoding="utf-8"))
            self.assertEqual(parsed.app_version, "3.7.0")
            self.assertEqual(parsed.app_hash, FAKE_HASH)
            self.assertEqual(stat.S_IMODE(source_path.stat().st_mode), 0o640)

    def test_contract_failure_cannot_write_source(self) -> None:
        source_content = SOURCE_PATH.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source_path = directory / "source.nix"
            source_path.write_text(source_content, encoding="utf-8")
            with (
                patch.object(update, "__file__", str(directory / "update.py")),
                patch.object(
                    update,
                    "_discover_release",
                    return_value=update._Release("3.7.0", "v3.7.0"),
                ),
                patch.object(update, "_resolve_revision", return_value=FAKE_REVISION),
                patch.object(
                    update,
                    "_validate_release_contract",
                    side_effect=SystemExit(1),
                ),
                patch.object(update, "_prefetch_source_hash") as prefetch,
                self.assertRaises(SystemExit),
            ):
                update._main([])
            self.assertEqual(source_path.read_text(encoding="utf-8"), source_content)
            prefetch.assert_not_called()

    def test_help_does_not_need_network_or_nix(self) -> None:
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("update.py")), "--help"],
            capture_output=True,
            text=True,
            check=False,
            env={
                key: value for key, value in os.environ.items() if key != "PYTHONPATH"
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--refresh", result.stdout)


if __name__ == "__main__":
    unittest.main()
