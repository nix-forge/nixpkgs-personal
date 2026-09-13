"""Exercise copied-package updates without network requests or Nix builds."""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update


class UpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.package = Path(self.temporary.name) / "standalone ${package}"
        shutil.copytree(Path(update.__file__).parent, self.package)
        self.source = self.package / "source.nix"
        self.original = self.source.read_bytes()
        self.existing = update._parse_existing(self.original.decode())
        self.release = update._Release(
            version="99.0.0",
            darwin_url=self.existing.darwin_url,
            darwin_hash_sri=self.existing.darwin_hash,
            linux_rev="v99.0.0",
            electron_version=self.existing.electron_version,
            electron_dist_url=self.existing.electron_dist_url,
            electron_shasums_url=self.existing.electron_shasums_url,
            electron_headers_url=self.existing.electron_headers_url,
        )
        self.enterContext(
            patch.object(update, "__file__", str(self.package / "update.py"))
        )
        self.enterContext(patch.object(update, "_get_nix_binary", return_value="nix"))
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        self.enterContext(contextlib.redirect_stderr(io.StringIO()))

    def test_help_from_copied_package_without_nix(self) -> None:
        result = subprocess.run(
            [sys.executable, str(self.package / "update.py"), "--help"],
            cwd=self.temporary.name,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--nixpkgs", result.stdout)

    def test_dependency_build_selects_linux_and_local_recipe(self) -> None:
        completed = subprocess.CompletedProcess(
            [], 1, "", f"got: {self.existing.pnpm_hash}"
        )
        with patch.object(update.subprocess, "run", return_value=completed) as run:
            actual = update._nix_build_fod_hash(
                package_dir=self.package,
                nixpkgs_path=Path("/nix/store/upstream"),
                attr="pnpmDeps",
                label="pnpm mirror",
            )
        self.assertEqual(actual, self.existing.pnpm_hash)
        command = run.call_args.args[0]
        expression = command[command.index("--expr") + 1]
        self.assertIn('system = "x86_64-linux"', expression)
        self.assertIn("pkgs.callPackage", expression)
        self.assertIn("/package.nix", expression)
        self.assertIn(r"\${package}", expression)
        self.assertNotIn("#t3-code", expression)
        self.assertIn("--impure", command)

    def test_nixpkgs_selector_is_resolved_once(self) -> None:
        result = subprocess.CompletedProcess(
            [], 0, json.dumps({"path": "/nix/store/upstream"}), ""
        )
        with patch.object(update.subprocess, "run", return_value=result) as run:
            self.assertEqual(
                update._resolve_nixpkgs("github:NixOS/nixpkgs/revision"),
                Path("/nix/store/upstream"),
            )
        self.assertEqual(run.call_args.args[0][-1], "github:NixOS/nixpkgs/revision")

    def test_unrelated_build_failure_does_not_return_a_hash(self) -> None:
        result = subprocess.CompletedProcess([], 1, "", "builder is unavailable")
        with (
            patch.object(update.subprocess, "run", return_value=result),
            self.assertRaises(SystemExit),
        ):
            update._nix_build_fod_hash(
                package_dir=self.package,
                nixpkgs_path=Path("/nix/store/upstream"),
                attr="cargoDeps",
                label="cargo vendor",
            )

    def test_dry_run_preserves_source_and_passes_selector(self) -> None:
        meta = update._ReleaseMeta(
            version=self.release.version,
            darwin_url=self.release.darwin_url,
            darwin_hash_sri=self.release.darwin_hash_sri,
            linux_rev=self.release.linux_rev,
        )
        resolved = update._ResolvedSource(
            existing=self.existing,
            release=self.release,
            darwin_hash_sri=self.existing.darwin_hash,
            linux_hash_sri=self.existing.linux_hash,
            pnpm_hash_sri=self.existing.pnpm_hash,
            cargo_hash_sri=self.existing.cargo_hash,
            electron_dist_hash_sri=self.existing.electron_dist_hash,
            electron_shasums_hash_sri=self.existing.electron_shasums_hash,
            electron_headers_hash_sri=self.existing.electron_headers_hash,
        )
        with (
            patch.object(update, "_discover_release_meta", return_value=meta),
            patch.object(update, "_discover_release", return_value=self.release),
            patch.object(update, "_resolve_hashes", return_value=resolved) as resolve,
        ):
            self.assertEqual(
                update._main(["--dry-run", "--nixpkgs", "path:/upstream"]), 0
            )
        self.assertEqual(resolve.call_args.kwargs["nixpkgs"], "path:/upstream")
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_invalid_nixpkgs_metadata_fails(self) -> None:
        for stdout in ("invalid json", "[]", '{"path": "relative"}'):
            with self.subTest(stdout=stdout):
                result = subprocess.CompletedProcess([], 0, stdout, "")
                with (
                    patch.object(update.subprocess, "run", return_value=result),
                    self.assertRaises(SystemExit),
                ):
                    update._resolve_nixpkgs("nixpkgs")

    def test_candidate_is_cleaned_after_success(self) -> None:
        self._check_candidate_cleanup(failure=False)

    def test_read_only_package_can_prepare_candidate(self) -> None:
        self.package.chmod(0o555)
        try:
            self._check_candidate_cleanup(failure=False)
        finally:
            self.package.chmod(0o755)

    def test_candidate_is_cleaned_after_failure(self) -> None:
        self._check_candidate_cleanup(failure=True)

    def _check_candidate_cleanup(self, *, failure: bool) -> None:
        candidates: list[Path] = []

        def build_hash(
            *, package_dir: Path, nixpkgs_path: Path, attr: str, label: str
        ) -> str:
            candidates.append(package_dir)
            self.assertEqual(self.source.read_bytes(), self.original)
            self.assertEqual(nixpkgs_path, Path("/nix/store/upstream"))
            seed = update._parse_existing((package_dir / "source.nix").read_text())
            self.assertEqual(seed.version, "99.0.0")
            self.assertEqual(seed.pnpm_hash, update.FAKE_HASH)
            self.assertTrue((package_dir / "linux.nix").is_file())
            if failure:
                raise RuntimeError("builder failed")
            return (
                self.existing.pnpm_hash
                if attr == "pnpmDeps"
                else self.existing.cargo_hash
            )

        with (
            patch.object(
                update, "_prefetch_hash", return_value=self.existing.darwin_hash
            ),
            patch.object(
                update,
                "_resolve_nixpkgs",
                return_value=Path("/nix/store/upstream"),
            ),
            patch.object(update, "_nix_build_fod_hash", side_effect=build_hash),
        ):
            if failure:
                with self.assertRaisesRegex(RuntimeError, "builder failed"):
                    update._resolve_hashes(
                        self.existing, self.release, nixpkgs="nixpkgs"
                    )
            else:
                resolved = update._resolve_hashes(
                    self.existing, self.release, nixpkgs="nixpkgs"
                )
                self.assertEqual(resolved.pnpm_hash_sri, self.existing.pnpm_hash)
        self.assertTrue(candidates)
        self.assertTrue(all(not candidate.exists() for candidate in candidates))
        self.assertEqual(self.source.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
