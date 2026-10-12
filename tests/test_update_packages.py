"""Check safe partial submission by the package updater dispatcher."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/update-packages.py"
SPEC = importlib.util.spec_from_file_location("update_packages", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load update-packages.py")
update_packages = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = update_packages
SPEC.loader.exec_module(update_packages)


class PartialUpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.updaters = {
            name: update_packages._PackageUpdater(
                name, Path(f"/example/{name}/update.py")
            )
            for name in ("first", "second")
        }

    def test_unchanged_failure_allows_successful_package_changes(self) -> None:
        with (
            patch.object(
                update_packages, "_discover_updaters", return_value=self.updaters
            ),
            patch.object(update_packages, "_run_updater", side_effect=[0, 1]),
            patch.object(
                update_packages,
                "_working_tree_snapshot",
                side_effect=[b"", b"", b"changed", b"changed", b"changed"],
            ),
        ):
            self.assertEqual(
                update_packages._main(["--all", "--keep-going", "--allow-partial"]), 0
            )

    def test_failed_updater_must_leave_tree_unchanged(self) -> None:
        with (
            patch.object(
                update_packages, "_discover_updaters", return_value=self.updaters
            ),
            patch.object(update_packages, "_run_updater", return_value=1),
            patch.object(
                update_packages,
                "_working_tree_snapshot",
                side_effect=[b"", b"", b"changed"],
            ),
        ):
            self.assertEqual(
                update_packages._main(["--all", "--keep-going", "--allow-partial"]), 1
            )

    def test_no_successful_changes_remains_failure(self) -> None:
        with (
            patch.object(
                update_packages, "_discover_updaters", return_value=self.updaters
            ),
            patch.object(update_packages, "_run_updater", return_value=1),
            patch.object(update_packages, "_working_tree_snapshot", return_value=b""),
        ):
            self.assertEqual(
                update_packages._main(["--all", "--keep-going", "--allow-partial"]), 1
            )

    def test_discovery_lists_each_updater_without_running_it(self) -> None:
        with (
            patch.object(
                update_packages, "_discover_updaters", return_value=self.updaters
            ),
            patch.object(update_packages, "_run_updater") as run_updater,
            patch.object(update_packages, "_stdout") as output,
        ):
            self.assertEqual(update_packages._main(["--list-json"]), 0)
        output.assert_called_once()
        self.assertEqual(json.loads(output.call_args.args[0]), ["first", "second"])
        run_updater.assert_not_called()

    def test_discovery_rejects_empty_catalog(self) -> None:
        with (
            patch.object(update_packages, "_discover_updaters", return_value={}),
            self.assertRaises(SystemExit),
        ):
            update_packages._main(["--list-json"])


class PublisherTests(unittest.TestCase):
    """Execute the real publish step with isolated Git and API/tool adapters."""

    def setUp(self) -> None:
        self.fixture = tempfile.TemporaryDirectory()
        self.addCleanup(self.fixture.cleanup)
        self.root = Path(self.fixture.name)
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        self.remote = self.root / "remote.git"
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.env = {
            **os.environ,
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "PATH": str(self.tools) + os.pathsep + os.environ["PATH"],
            "PACKAGE": "first",
            "REPOSITORY": "example/repository",
            "BASE_BRANCH": "main",
            "GH_LOG": str(self.root / "gh.jsonl"),
            "NIX_LOG": str(self.root / "nix.jsonl"),
        }
        self.git("init", "-q", "--initial-branch=main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        for name in ("first", "second"):
            self.write(f"pkgs/by-name/{name[:2]}/{name}/source.txt", "1\n")
        self.write("docs/catalog.md", "first=1\nsecond=1\n")
        self.write("README.md", "Reviewed root documentation.\n")
        self.commit("base")
        subprocess.run(
            ["git", "init", "-q", "--bare", str(self.remote)],
            env=self.env,
            check=True,
            capture_output=True,
        )
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-q", "origin", "main")
        self.adapter(
            "gh",
            r"""
import json
import os
import sys
from pathlib import Path
args = sys.argv[1:]
with Path(os.environ["GH_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\n")
if args[:2] == ["pr", "list"]:
    if "url,author" in args:
        print(os.environ.get("EXISTING_PR", ""))
    else:
        print(os.environ.get("FOREIGN_PR", ""))
elif args[:2] == ["pr", "view"]:
    print(os.environ.get("MERGEABLE", "MERGEABLE"))
elif args[:2] == ["pr", "create"]:
    print("https://github.com/example/repository/pull/1")
elif args[:1] == ["api"]:
    path = args[1]
    workflow = path.split("/actions/workflows/", 1)[1].split("/", 1)[0]
    names = ["ci.yml", "codeql.yml", "dependency-review.yml", "dco.yml", "fuzz.yml"]
    identity = names.index(workflow) + 1
    if os.environ.get("API_FAIL_WORKFLOW") == workflow:
        raise SystemExit(1)
    if "/runs?" not in path:
        print(json.dumps({"id": identity, "path": ".github/workflows/" + workflow, "state": "active"}))
    else:
        current_sha = path.split("head_sha=", 1)[1].split("&", 1)[0]
        present = json.loads(os.environ.get("PRESENT_WORKFLOWS", "{}"))
        records = []
        if workflow in present:
            calls = [json.loads(line) for line in Path(os.environ["GH_LOG"]).read_text().splitlines()]
            reads = sum(call[:1] == ["api"] and "/" + workflow + "/runs?" in call[1] for call in calls)
            if os.environ.get("DELAYED_WORKFLOW") != workflow or reads >= 2:
                record = {
                    "id": 100 + identity, "workflow_id": identity,
                    "path": ".github/workflows/" + workflow,
                    "head_sha": os.environ.get("PRESENT_HEAD", current_sha),
                    "head_branch": "automation/package-updates/" + os.environ["PACKAGE"],
                    "repository": {"full_name": os.environ["REPOSITORY"]},
                    "head_repository": {"full_name": os.environ["REPOSITORY"]},
                    "event": "workflow_dispatch", "run_attempt": 1,
                    "status": "completed", "conclusion": present[workflow],
                }
                if os.environ.get("WRONG_EVENT_WORKFLOW") == workflow:
                    record["event"] = "schedule"
                if os.environ.get("WRONG_REPOSITORY_WORKFLOW") == workflow:
                    record["head_repository"] = {"full_name": "foreign/repository"}
                records.append(record)
        print(json.dumps({"workflow_runs": records, "total_count": len(records)}))
""",
        )
        self.adapter(
            "nix",
            r"""
import json
import os
import sys
from pathlib import Path
with Path(os.environ["NIX_LOG"]).open("a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\n")
if os.environ.get("GENERATOR_FAIL"):
    raise SystemExit(1)
rows = [name + "=" + Path("pkgs/by-name/" + name[:2] + "/" + name + "/source.txt").read_text().strip()
        for name in ("first", "second")]
Path("docs/catalog.md").write_text("\n".join(rows) + "\n")
if os.environ.get("GENERATOR_EXTRA"):
    Path("README.md").write_text("unexpected generator mutation\n")
""",
        )

        self.adapter("sleep", "")

    def adapter(self, name: str, body: str) -> None:
        path = self.tools / name
        path.write_text("#!" + sys.executable + "\n" + textwrap.dedent(body))
        path.chmod(0o755)

    def write(self, name: str, contents: str) -> None:
        path = self.checkout / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(self.checkout), *args],
            env=self.env,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()

    def commit(self, message: str) -> None:
        self.git("add", "-A")
        self.git("commit", "-qm", message)

    def publish(self) -> subprocess.CompletedProcess[str]:
        workflow = SCRIPT.parents[1] / ".github/workflows/update-packages.yml"
        step = workflow.read_text().split(
            "      - name: Publish package pull request\n", 1
        )[1]
        shell = textwrap.dedent(step.split("        run: |\n", 1)[1])
        return subprocess.run(
            ["bash", "-c", shell],
            cwd=self.checkout,
            env=self.env,
            check=False,
            capture_output=True,
            text=True,
        )

    def api_calls(self) -> list[list[str]]:
        log = self.root / "gh.jsonl"
        return (
            [json.loads(line) for line in log.read_text().splitlines()]
            if log.exists()
            else []
        )

    def old_pr(self) -> None:
        self.git("switch", "-qc", "automation/package-updates/first")
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        self.write("docs/catalog.md", "first=2\nsecond=1\n")
        self.commit("old bot update")
        self.git("push", "-q", "origin", "HEAD")
        self.env["PRESENT_HEAD"] = self.git("rev-parse", "HEAD")
        self.env["PRESENT_WORKFLOWS"] = json.dumps(
            dict.fromkeys(
                (
                    "ci.yml",
                    "codeql.yml",
                    "dependency-review.yml",
                    "dco.yml",
                    "fuzz.yml",
                ),
                "success",
            )
        )
        self.git("switch", "-q", "main")
        self.env["EXISTING_PR"] = "https://github.com/example/repository/pull/1"

    def test_published_update_contains_generated_catalog_and_one_package(self) -> None:
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("show", "HEAD:docs/catalog.md"), "first=2\nsecond=1")
        self.assertEqual(
            set(
                self.git(
                    "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"
                ).splitlines()
            ),
            {"pkgs/by-name/fi/first/source.txt", "docs/catalog.md"},
        )
        self.assertIn("Signed-off-by:", self.git("show", "-s", "--format=%B", "HEAD"))

    def test_publisher_dispatches_one_complete_validation_set(self) -> None:
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        workflows = [
            call[2] for call in self.api_calls() if call[:2] == ["workflow", "run"]
        ]
        self.assertEqual(
            workflows,
            ["ci.yml", "codeql.yml", "dependency-review.yml", "dco.yml", "fuzz.yml"],
        )

    def test_updater_cannot_edit_catalog_or_other_packages(self) -> None:
        for path in (
            "docs/catalog.md",
            "pkgs/by-name/se/second/source.txt",
            "README.md",
        ):
            with self.subTest(path=path):
                self.write(path, "unreviewed updater mutation\n")
                result = self.publish()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Updater changed a file outside", result.stderr)
                self.assertFalse((self.root / "nix.jsonl").exists())
                self.assertEqual(self.api_calls(), [])
                self.git("reset", "--hard", "HEAD")

    def test_generator_failure_never_publishes(self) -> None:
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        self.env["GENERATOR_FAIL"] = "1"
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertEqual(self.api_calls(), [])

    def test_generator_cannot_edit_additional_repository_files(self) -> None:
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        self.env["GENERATOR_EXTRA"] = "1"
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside", result.stderr)
        self.assertEqual(self.api_calls(), [])

    def test_existing_pr_refreshes_catalog_after_another_package_merges(self) -> None:
        self.old_pr()
        self.write("pkgs/by-name/se/second/source.txt", "2\n")
        self.write("docs/catalog.md", "first=1\nsecond=2\n")
        self.commit("another reviewed package")
        base = self.git("rev-parse", "HEAD")
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("show", "HEAD:docs/catalog.md"), "first=2\nsecond=2")
        self.assertEqual(self.git("rev-parse", "HEAD^"), base)

    def test_identical_mergeable_pr_is_not_rewritten(self) -> None:
        self.old_pr()
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        before = self.git(
            "ls-remote", "origin", "refs/heads/automation/package-updates/first"
        )
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git(
                "ls-remote", "origin", "refs/heads/automation/package-updates/first"
            ),
            before,
        )
        self.assertFalse(
            any(call[:2] == ["workflow", "run"] for call in self.api_calls())
        )

    def test_interrupted_publication_resumes_only_missing_validation(self) -> None:
        self.old_pr()
        self.env["PRESENT_WORKFLOWS"] = json.dumps({
            "ci.yml": "failure",
            "codeql.yml": "success",
        })
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        before = self.git(
            "ls-remote", "origin", "refs/heads/automation/package-updates/first"
        )
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git(
                "ls-remote", "origin", "refs/heads/automation/package-updates/first"
            ),
            before,
        )
        self.assertEqual(
            [call[2] for call in self.api_calls() if call[:2] == ["workflow", "run"]],
            ["dependency-review.yml", "dco.yml", "fuzz.yml"],
        )
        merge = next(call for call in self.api_calls() if call[:2] == ["pr", "merge"])
        self.assertEqual(merge[-2:], ["--match-head-commit", self.env["PRESENT_HEAD"]])

    def test_delayed_validation_visibility_does_not_duplicate_run(self) -> None:
        self.old_pr()
        self.env["DELAYED_WORKFLOW"] = "dco.yml"
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(
            any(call[:2] == ["workflow", "run"] for call in self.api_calls())
        )
        reads = [
            call
            for call in self.api_calls()
            if call[:1] == ["api"] and "/dco.yml/runs?" in call[1]
        ]
        self.assertEqual(len(reads), 2)

    def test_wrong_repository_or_event_cannot_supply_validation(self) -> None:
        self.old_pr()
        self.env["WRONG_REPOSITORY_WORKFLOW"] = "ci.yml"
        self.env["WRONG_EVENT_WORKFLOW"] = "dco.yml"
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [call[2] for call in self.api_calls() if call[:2] == ["workflow", "run"]],
            ["ci.yml", "dco.yml"],
        )

    def test_metadata_api_error_cannot_enable_auto_merge(self) -> None:
        self.old_pr()
        self.env["API_FAIL_WORKFLOW"] = "ci.yml"
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        self.assertNotEqual(self.publish().returncode, 0)
        self.assertFalse(any(call[:2] == ["pr", "merge"] for call in self.api_calls()))

    def test_conflicting_pr_refreshes_even_when_target_files_match(self) -> None:
        self.old_pr()
        base = self.git("rev-parse", "HEAD")
        self.write("pkgs/by-name/fi/first/source.txt", "2\n")
        self.env["MERGEABLE"] = "CONFLICTING"
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD^"), base)
        self.assertTrue(
            any(call[:2] == ["workflow", "run"] for call in self.api_calls())
        )


if __name__ == "__main__":
    unittest.main()
