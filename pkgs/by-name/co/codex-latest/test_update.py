"""Exercise stable selection and complete dependency refresh with isolated fixtures."""

from __future__ import annotations

import copy
import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import update

REVISION = "1" * 40
HASH = "sha256-ERERERERERERERERERERERERERERERERERERERERERE="
LOCK = b'[[package]]\nname = "v8"\nversion = "150.4.0"\nsource = "registry+https://github.com/rust-lang/crates.io-index"\n'


def release(version="0.162.1", **fields) -> dict:
    return {
        "tag_name": f"rust-v{version}",
        "draft": False,
        "prerelease": False,
        **fields,
    }


class ReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.current = {
            "version": "0.162.0",
            "rev": "2" * 40,
            "hash": HASH,
            "cargoHash": HASH,
            "v8": {
                "version": "150.4.0",
                "sources": {system: {} for system in update.TARGETS},
            },
        }

    def test_prereleases_and_drafts_are_not_selected(self) -> None:
        for fixture in [
            release(prerelease=True),
            release(draft=True),
            release(tag_name="rust-v0.163.0-alpha.1"),
        ]:
            with (
                self.subTest(fixture=fixture),
                self.assertRaisesRegex(ValueError, "stable"),
            ):
                update.release_identity(fixture)

    def test_v8_is_selected_from_the_immutable_release_lock(self) -> None:
        self.assertEqual(update.v8_version(LOCK), "150.4.0")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            update.v8_version(LOCK + LOCK)
        with self.assertRaisesRegex(ValueError, "registry"):
            update.v8_version(LOCK.replace(b"registry+", b"git+"))

    def test_downgrade_or_invalid_commit_does_not_download(self) -> None:
        for fixture, revision in [(release("0.161.0"), REVISION), (release(), "tag")]:
            with (
                patch.object(update, "prefetch") as fetch,
                self.assertRaises(ValueError),
            ):
                update.candidate(self.current, fixture, revision, LOCK)
            fetch.assert_not_called()

    def test_same_release_cannot_change_its_commit_or_v8(self) -> None:
        self.current["version"] = "0.162.1"
        with self.assertRaisesRegex(ValueError, "changed identity"):
            update.candidate(self.current, release(), REVISION, LOCK)

    def test_noop_does_not_fetch_or_rebuild_dependencies(self) -> None:
        self.current.update(version="0.162.1", rev=REVISION)
        with (
            patch.object(update, "prefetch") as fetch,
            patch.object(update, "cargo_hash") as cargo,
        ):
            self.assertEqual(
                update.candidate(self.current, release(), REVISION, LOCK), self.current
            )
        fetch.assert_not_called()
        cargo.assert_not_called()

    def test_every_platform_runtime_is_pinned_before_cargo_publication(self) -> None:
        original = copy.deepcopy(self.current)
        with (
            patch.object(
                update, "prefetch", return_value=(HASH, Path("/fixture"))
            ) as fetch,
            patch.object(update, "cargo_hash", return_value=HASH) as cargo,
        ):
            result = update.candidate(self.current, release(), REVISION, LOCK)
        self.assertEqual(result["rev"], REVISION)
        self.assertEqual(result["cargoHash"], HASH)
        self.assertEqual(
            set(result["v8"]["sources"]),
            {"x86_64-linux", "aarch64-linux", "aarch64-darwin"},
        )
        self.assertEqual(fetch.call_count, 7)
        urls = [call.args[0] for call in fetch.call_args_list]
        self.assertEqual(
            urls[0], f"https://github.com/openai/codex/archive/{REVISION}.tar.gz"
        )
        self.assertIn(
            "https://github.com/denoland/rusty_v8/releases/download/v150.4.0/src_binding_release_aarch64-apple-darwin.rs",
            urls,
        )
        self.assertEqual(
            cargo.call_args.args[0]["v8"]["sources"], result["v8"]["sources"]
        )
        self.assertEqual(self.current, original)

    def test_failed_last_artifact_does_not_mutate_current_pins(self) -> None:
        original = copy.deepcopy(self.current)
        with (
            patch.object(
                update,
                "prefetch",
                side_effect=[(HASH, Path("/fixture"))] * 6
                + [ValueError("missing binding")],
            ),
            self.assertRaisesRegex(ValueError, "missing binding"),
        ):
            update.candidate(self.current, release(), REVISION, LOCK)
        self.assertEqual(self.current, original)

    def test_annotated_release_tag_is_peeled_to_its_commit(self) -> None:
        tag_object = "3" * 40
        with patch.object(
            update,
            "json_metadata",
            side_effect=[
                {
                    "ref": "refs/tags/rust-v0.162.1",
                    "object": {"type": "tag", "sha": tag_object},
                },
                {"object": {"type": "commit", "sha": REVISION}},
            ],
        ) as query:
            self.assertEqual(update.resolve_tag("rust-v0.162.1"), REVISION)
        self.assertEqual(
            query.call_args.args[0],
            f"https://api.github.com/repos/openai/codex/git/tags/{tag_object}",
        )

    def test_unexpected_refs_and_tag_cycles_are_rejected(self) -> None:
        with (
            patch.object(
                update,
                "json_metadata",
                return_value={"ref": "refs/heads/rust-v0.162.1"},
            ),
            self.assertRaisesRegex(ValueError, "unexpected release tag"),
        ):
            update.resolve_tag("rust-v0.162.1")
        target = {"type": "tag", "sha": "3" * 40}
        with (
            patch.object(
                update,
                "json_metadata",
                side_effect=[{"ref": "refs/tags/rust-v0.162.1", "object": target}]
                + [{"object": target}] * 4,
            ),
            self.assertRaisesRegex(ValueError, "too deep"),
        ):
            update.resolve_tag("rust-v0.162.1")

    def test_release_is_resolved_once_and_lock_fetch_uses_commit(self) -> None:
        with (
            patch.object(
                update,
                "json_metadata",
                side_effect=[
                    release(),
                    {
                        "ref": "refs/tags/rust-v0.162.1",
                        "object": {"type": "commit", "sha": REVISION},
                    },
                ],
            ) as query,
            patch.object(update, "metadata", return_value=LOCK) as fetch,
            patch.object(update, "candidate", return_value={}) as candidate,
        ):
            update.discover(self.current)
        self.assertEqual(query.call_count, 2)
        fetch.assert_called_once_with(
            f"https://raw.githubusercontent.com/openai/codex/{REVISION}/codex-rs/Cargo.lock"
        )
        self.assertEqual(candidate.call_args.args[2], REVISION)


FORK_REVISION = "3" * 40
FORK_SOURCE = f"git+{update.V8_FORK}?rev={FORK_REVISION}#{FORK_REVISION}"
FORK_LOCK = (
    f'[[package]]\nname = "v8"\nversion = "152.2.0"\nsource = "{FORK_SOURCE}"\n'
).encode()
FORK_MANIFEST = (
    '[workspace.dependencies]\nv8 = "=152.2.0"\n'
    f'[patch.crates-io.v8]\ngit = "{update.V8_FORK}"\nrev = "{FORK_REVISION}"\n'
).encode()
FORK_CONSUMER = (
    b'[dependencies.v8]\nworkspace = true\nfeatures = ["v8_enable_sandbox"]\n'
)


class ForkRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runtime = update.v8_identity(FORK_LOCK)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.trusted = {}
        self.files = {}
        for target in update.TARGETS.values():
            manifest = f"rusty_v8_{update.V8_PROFILE}_{target}.sha256"
            contents = (
                "11" * 32
                + f"  librusty_v8_{update.V8_PROFILE}_{target}.a.gz\n"
                + "11" * 32
                + f"  src_binding_{update.V8_PROFILE}_{target}.rs\n"
            ).encode()
            path = self.root / manifest
            path.write_bytes(contents)
            self.files[manifest] = path
            self.trusted[manifest] = hashlib.sha256(contents).hexdigest()

    def fetch(self, url: str, *, unpack: bool = False):
        self.assertFalse(unpack)
        filename = url.rsplit("/", 1)[1]
        if filename in self.files:
            return update.sri(self.trusted[filename]), self.files[filename]
        return HASH, self.root

    def test_only_the_reviewed_fork_with_matching_full_revisions_is_accepted(self):
        self.assertEqual(self.runtime["artifactProfile"], update.V8_PROFILE)
        self.assertEqual(self.runtime["dependencySource"], FORK_SOURCE)
        invalid = [
            FORK_LOCK.replace(b"seanh-oai", b"unknown"),
            FORK_LOCK.replace(FORK_REVISION.encode(), b"main"),
            FORK_LOCK.replace(
                ("#" + FORK_REVISION).encode(), ("#" + "4" * 40).encode()
            ),
            FORK_LOCK.replace(b"?rev=", b"?branch="),
        ]
        for lock in invalid:
            with self.subTest(lock=lock), self.assertRaises(ValueError):
                update.v8_identity(lock)

    def test_fork_source_and_sandbox_consumer_are_checked_at_release_commit(self):
        manifest = "\n".join(
            f"{digest}  {name}" for name, digest in self.trusted.items()
        )
        with patch.object(
            update,
            "metadata",
            side_effect=[FORK_MANIFEST, FORK_CONSUMER, manifest.encode()],
        ) as fetch:
            self.assertEqual(update.fork_manifest(REVISION, self.runtime), self.trusted)
        for call in fetch.call_args_list:
            self.assertIn(f"/{REVISION}/", call.args[0])

    def test_fork_manifest_or_feature_mismatch_fails_before_asset_fetch(self):
        for manifest, consumer in [
            (FORK_MANIFEST.replace(FORK_REVISION.encode(), b"4" * 40), FORK_CONSUMER),
            (FORK_MANIFEST.replace(b"=152.2.0", b"=152.1.0"), FORK_CONSUMER),
            (FORK_MANIFEST, FORK_CONSUMER.replace(b"v8_enable_sandbox", b"other")),
        ]:
            with (
                self.subTest(manifest=manifest, consumer=consumer),
                patch.object(update, "metadata", side_effect=[manifest, consumer]),
                patch.object(update, "prefetch") as prefetch,
                self.assertRaises(ValueError),
            ):
                update.fork_manifest(REVISION, self.runtime)
            prefetch.assert_not_called()

    def test_duplicate_malformed_and_empty_checksum_manifests_are_rejected(self):
        entry = b"11" * 32 + b"  expected.rs\n"
        for contents in [b"", entry + entry, b"xyz  file", b"11" * 32 + b"  ../file\n"]:
            with self.subTest(contents=contents), self.assertRaises(ValueError):
                update.checksum_entries(contents)

    def test_all_artifacts_are_checked_against_the_immutable_manifest_chain(self):
        with (
            patch.object(update, "fork_manifest", return_value=self.trusted),
            patch.object(update, "prefetch", side_effect=self.fetch) as fetch,
        ):
            sources = update.runtime_sources(REVISION, self.runtime)
        self.assertEqual(set(sources), set(update.TARGETS))
        self.assertEqual(fetch.call_count, 9)
        for assets in sources.values():
            for artifact in assets.values():
                self.assertIn(
                    "/openai/codex/releases/download/rusty-v8-v152.2.0/",
                    artifact["url"],
                )
                self.assertIn(update.V8_PROFILE, artifact["url"])
                self.assertEqual(artifact["hash"], HASH)

    def test_missing_target_and_incorrect_manifest_hash_fail_closed(self):
        for trusted, returned_hash in [({}, HASH), (self.trusted, HASH)]:
            with (
                self.subTest(trusted=trusted),
                patch.object(update, "fork_manifest", return_value=trusted),
                patch.object(
                    update, "prefetch", return_value=(returned_hash, self.root)
                ),
                self.assertRaises(ValueError),
            ):
                update.runtime_sources(REVISION, self.runtime)

    def test_returned_manifest_bytes_are_also_checked(self):
        first = min(update.TARGETS.items())[1]
        filename = f"rusty_v8_{update.V8_PROFILE}_{first}.sha256"
        self.files[filename].write_bytes(b"changed")
        with (
            patch.object(update, "fork_manifest", return_value=self.trusted),
            patch.object(update, "prefetch", side_effect=self.fetch),
            self.assertRaisesRegex(ValueError, "bytes disagree"),
        ):
            update.runtime_sources(REVISION, self.runtime)

    def test_unexpected_asset_and_asset_digest_mismatch_fail_closed(self):
        first = min(update.TARGETS.items())[1]
        filename = f"rusty_v8_{update.V8_PROFILE}_{first}.sha256"
        path = self.files[filename]
        original = path.read_bytes()
        for contents, message in [
            (
                original.replace(b"src_binding_", b"unexpected_"),
                "exactly the asset pair",
            ),
            (original.replace(b"11" * 32, b"22" * 32), "artifact hash disagrees"),
        ]:
            path.write_bytes(contents)
            self.trusted[filename] = hashlib.sha256(contents).hexdigest()
            with (
                self.subTest(message=message),
                patch.object(update, "fork_manifest", return_value=self.trusted),
                patch.object(update, "prefetch", side_effect=self.fetch),
                self.assertRaisesRegex(ValueError, message),
            ):
                update.runtime_sources(REVISION, self.runtime)

    def test_same_version_requires_matching_source_and_profile_without_downloads(self):
        current = {
            "version": "0.167.0",
            "rev": REVISION,
            "v8": {**self.runtime, "sources": {}},
        }
        with (
            patch.object(update, "metadata") as metadata,
            patch.object(update, "prefetch") as fetch,
        ):
            self.assertEqual(
                update.candidate(current, release("0.167.0"), REVISION, FORK_LOCK),
                current,
            )
        metadata.assert_not_called()
        fetch.assert_not_called()
        for field in ["dependencySource", "artifactProfile"]:
            changed = copy.deepcopy(current)
            runtime = changed["v8"]
            assert isinstance(runtime, dict)
            runtime.pop(field)
            with (
                self.subTest(field=field),
                self.assertRaisesRegex(ValueError, "changed identity"),
            ):
                update.candidate(changed, release("0.167.0"), REVISION, FORK_LOCK)

    def test_success_records_full_runtime_identity_before_cargo_publication(self):
        current = {"version": "0.163.0", "rev": "2" * 40, "v8": {"version": "150.4.0"}}
        with (
            patch.object(update, "prefetch", return_value=(HASH, self.root)),
            patch.object(update, "runtime_sources", return_value={"fixture": {}}),
            patch.object(update, "cargo_hash", return_value=HASH) as cargo,
        ):
            result = update.candidate(current, release("0.167.0"), REVISION, FORK_LOCK)
        self.assertEqual(result["v8"]["dependencySource"], FORK_SOURCE)
        self.assertEqual(result["v8"]["artifactProfile"], update.V8_PROFILE)
        self.assertEqual(cargo.call_args.args[0]["v8"], result["v8"])

    def test_failure_in_new_runtime_chain_does_not_mutate_or_prepare_cargo(self):
        current = {"version": "0.163.0", "rev": "2" * 40, "v8": {"version": "150.4.0"}}
        original = copy.deepcopy(current)
        with (
            patch.object(update, "prefetch", return_value=(HASH, self.root)),
            patch.object(
                update, "runtime_sources", side_effect=ValueError("untrusted asset")
            ),
            patch.object(update, "cargo_hash") as cargo,
            self.assertRaisesRegex(ValueError, "untrusted asset"),
        ):
            update.candidate(current, release("0.167.0"), REVISION, FORK_LOCK)
        cargo.assert_not_called()
        self.assertEqual(current, original)


class CargoTests(unittest.TestCase):
    def test_dependency_hash_is_verified_before_returning(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            scope = Path(directory) / "Nixpkgs ${with spaces}"
            scope.mkdir()
            (scope / "default.nix").write_text("{}: {}\n")
            with (
                patch.dict(os.environ, {"NIXPKGS_UPDATE_SOURCE": str(scope)}),
                patch.object(
                    update,
                    "run",
                    side_effect=[
                        Mock(returncode=1, stderr=f"got: {HASH}"),
                        Mock(returncode=0),
                    ],
                ) as command,
            ):
                self.assertEqual(update.cargo_hash({}), HASH)
                self.assertEqual(command.call_count, 2)
                arguments = command.call_args.args[0]
                self.assertIn(str(scope), arguments)
                candidate = Path(arguments[arguments.index("sourceFile") + 1])
                self.assertFalse(candidate.exists())

    def test_unrelated_build_failure_is_not_treated_as_a_new_hash(self) -> None:
        with tempfile.TemporaryDirectory() as scope:
            (Path(scope) / "default.nix").write_text("{}: {}\n")
            with (
                patch.dict(os.environ, {"NIXPKGS_UPDATE_SOURCE": scope}),
                patch.object(
                    update,
                    "run",
                    return_value=Mock(returncode=1, stderr="network failure"),
                ),
                self.assertRaisesRegex(ValueError, "one hash mismatch"),
            ):
                update.cargo_hash({})


if __name__ == "__main__":
    unittest.main()
