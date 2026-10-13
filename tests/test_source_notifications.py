"""Exercise package caller contracts against the verified shared release."""

import ast
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
PIN = "ab8e486d3d1c48edd116578e097a46eb0c8f5097"
ARCHIVE_SHA = "ec1e9099b62fc4f6738ccebef0803e417fd97aba7e078385a3535705590ba9e4"
FILES = ["ci.yml", "codeql.yml", "dependency-review.yml", "dco.yml", "fuzz.yml"]
SOURCE = "refs/heads/automation/package-updates-example"
QUEUE = "refs/heads/gh-readonly-queue/main/pr-7-example"


def expression(value, event="workflow_dispatch", ref=SOURCE, cancelled=False):
    """Evaluate the callers' boolean expressions.

    Raises:
        ValueError: An expression contains unsupported syntax or a name.

    """
    value = value.removeprefix("${{").removesuffix("}}").strip()
    if value in {"true", "false"}:
        return value == "true"
    replacements = {
        "github.event.repository.default_branch": "'main'",
        "github.event_name": repr(event),
        "github.ref": repr(ref),
        "inputs.build_expensive_font": "False",
        "inputs.build_expensive_audiomuse": "False",
    }
    for old, new in replacements.items():
        value = value.replace(old, new)
    value = value.replace("&&", " and ").replace("||", " or ")
    value = value.replace("!cancelled()", "not cancelled()")
    value = value.replace("!startsWith(", "not startsWith(")
    tree = ast.parse(value, mode="eval")
    allowed = (
        ast.Expression,
        ast.BoolOp,
        ast.And,
        ast.Or,
        ast.UnaryOp,
        ast.Not,
        ast.Compare,
        ast.Eq,
        ast.Constant,
        ast.Call,
        ast.Name,
        ast.Load,
    )
    if any(not isinstance(node, allowed) for node in ast.walk(tree)):
        raise ValueError("Unsupported callback expression")
    functions = {
        "always": lambda: True,
        "cancelled": lambda: cancelled,
        "startsWith": lambda text, prefix: text.startswith(prefix),
        "format": lambda text, *args: text.format(*args),
    }
    if any(
        isinstance(node, ast.Name) and node.id not in functions
        for node in ast.walk(tree)
    ):
        raise ValueError("Unknown callback expression name")

    def evaluate(node):
        if isinstance(node, ast.Expression):
            return evaluate(node.body)
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.BoolOp):
            for operand in node.values:
                result = evaluate(operand)
                if (isinstance(node.op, ast.And) and not result) or (
                    isinstance(node.op, ast.Or) and result
                ):
                    break
            return result
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            return not evaluate(node.operand)
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            return evaluate(node.left) == evaluate(node.comparators[0])
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            return functions[node.func.id](*(evaluate(arg) for arg in node.args))
        raise ValueError("Unsupported callback expression")

    return evaluate(tree)


class SourceNotificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflows = {
            name: yaml.load(
                (ROOT / ".github/workflows" / name).read_text(), Loader=yaml.BaseLoader
            )
            for name in FILES
        }
        cls.reconciler = yaml.load(
            (ROOT / ".github/workflows/reconcile-merge-queue.yml").read_text(),
            Loader=yaml.BaseLoader,
        )
        archive = Path(os.environ["SHARED_CI_ARCHIVE"])
        if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA:
            raise ValueError(
                "Shared CI archive differs from the verified v2.12 release"
            )
        with tarfile.open(archive) as bundle:

            def read(name):
                member = bundle.extractfile(f"nix-forge-ci-v2.12.0/{name}")
                if member is None:
                    raise ValueError("Shared release member is not a regular file")
                return member.read().decode()

            cls.action = yaml.load(
                read("actions/queue-completion/action.yml"), Loader=yaml.BaseLoader
            )
            cls.shared_dir = tempfile.TemporaryDirectory()
            cls.addClassCleanup(cls.shared_dir.cleanup)
            script = Path(cls.shared_dir.name) / "reconcile-queue.py"
            script.write_text(read("scripts/reconcile-queue.py"))
            spec = importlib.util.spec_from_file_location(
                "verified_shared_queue", script
            )
            if spec is None or spec.loader is None:
                raise ImportError("Unable to load verified shared reconciler")
            cls.queue = importlib.util.module_from_spec(spec)
            with patch.dict(
                os.environ,
                {"GH_REPO": "nix-forge/example", "QUEUE_WORKFLOWS": json.dumps(FILES)},
            ):
                spec.loader.exec_module(cls.queue)

    def test_dispatch_schema_and_exact_sixteen_gates(self):
        inputs = self.reconciler["on"]["workflow_dispatch"]["inputs"]
        self.assertEqual(
            set(inputs), {"source_run_id", "source_run_attempt", "source_activity"}
        )
        for value in inputs.values():
            self.assertEqual(value["type"], "string")
            self.assertEqual(value["required"], "false")
        # Source and queue writes are paced by the shared reconciler. A full
        # six-head sweep needs the consumer's own timeout, not the CI repo's.
        self.assertEqual(self.reconciler["jobs"]["reconcile"]["timeout-minutes"], "15")
        action = self.reconciler["jobs"]["reconcile"]["steps"][0]
        self.assertEqual(action["uses"], f"nix-forge/ci/actions/reconcile-queue@{PIN}")
        for external, internal in [
            ("source_run_id", "source-run-id"),
            ("source_run_attempt", "source-run-attempt"),
            ("source_activity", "source-activity"),
        ]:
            self.assertEqual(action["with"][internal], "${{ inputs." + external + " }}")
        checks = json.loads(action["with"]["package-source-checks"])
        self.assertEqual(set(checks), set(FILES))
        self.assertEqual(
            checks["ci.yml"],
            [
                "Build (x86_64-linux)",
                "Build (aarch64-linux)",
                "Build (aarch64-darwin)",
                "Lint and security",
                "Flake checks (x86_64-linux)",
                "Flake checks (aarch64-linux)",
                "Flake checks (aarch64-darwin)",
                "NUR compatibility / NUR (locked)",
                "NUR compatibility / NUR (unstable)",
                "Flake lock health",
                "Build (x86_64-linux 2/2)",
                "Build (aarch64-linux 2/2)",
            ],
        )
        self.assertEqual(checks["codeql.yml"], ["Analyze (python) / analyze"])
        self.assertEqual(
            checks["dependency-review.yml"], ["dependency-review / review"]
        )
        self.assertEqual(checks["dco.yml"], ["DCO sign-off"])
        self.assertEqual(checks["fuzz.yml"], ["Fuzz font path validation"])

    def test_notification_permissions_and_full_dependency_graph(self):
        for name, workflow in self.workflows.items():
            with self.subTest(workflow=name):
                self.assertEqual(workflow["permissions"], {})
                jobs = workflow["jobs"]
                self.assertIn("source-start", jobs)
                start = jobs["source-start"]
                completion = jobs["queue-completion"]
                self.assertEqual(start["name"], "Source validation start callback")
                self.assertEqual(completion["name"], "Queue completion callback")
                for job in [start, completion]:
                    self.assertEqual(job["permissions"], {"actions": "write"})
                    self.assertEqual(job["timeout-minutes"], "2")
                    self.assertEqual(len(job["steps"]), 1)
                    self.assertEqual(
                        job["steps"][0]["uses"],
                        f"nix-forge/ci/actions/queue-completion@{PIN}",
                    )
                self.assertEqual(start["continue-on-error"], "true")
                self.assertNotIn("needs", start)
                self.assertEqual(
                    set(completion["needs"]), set(jobs) - {"queue-completion"}
                )

                def ancestors(job_id, visited=frozenset(), graph=jobs):
                    self.assertNotIn(job_id, visited, "Validation dependency cycle")
                    needs = graph[job_id].get("needs", [])
                    needs = [needs] if isinstance(needs, str) else needs
                    result = set(needs)
                    for dependency in needs:
                        result |= ancestors(dependency, visited | {job_id}, graph)
                    return result

                for job_id, job in jobs.items():
                    if job_id in {"source-start", "queue-completion"}:
                        continue
                    self.assertNotIn("continue-on-error", job)
                    self.assertIn("source-start", ancestors(job_id))
                    if job.get("needs") == ["source-start"]:
                        self.assertIn("!cancelled()", job["if"])
                        if not job_id.startswith("expensive-"):
                            self.assertTrue(
                                expression(
                                    job["if"],
                                    event="pull_request",
                                    ref="refs/pull/7/merge",
                                )
                            )
                            self.assertTrue(expression(job["if"], ref=QUEUE))
                            self.assertTrue(expression(job["if"]))
                            self.assertFalse(expression(job["if"], cancelled=True))

    def test_actual_ref_guards_and_phases(self):
        for workflow in self.workflows.values():
            start = workflow["jobs"]["source-start"]
            completion = workflow["jobs"]["queue-completion"]
            self.assertEqual(
                start["steps"][0]["with"]["source-activity"], "in_progress"
            )
            phase = completion["steps"][0]["with"]["source-activity"]
            for event, ref, expected_start, expected_complete, expected_phase in [
                ("workflow_dispatch", SOURCE, True, True, "completed"),
                ("workflow_dispatch", QUEUE, False, True, ""),
                ("workflow_dispatch", "refs/heads/main", False, False, ""),
                (
                    "workflow_dispatch",
                    "refs/heads/gh-readonly-queue/other/pr-7",
                    False,
                    False,
                    "",
                ),
                (
                    "workflow_dispatch",
                    "refs/heads/example/automation/package-updates-test",
                    False,
                    False,
                    "",
                ),
                ("pull_request", SOURCE, False, False, "completed"),
                ("merge_group", QUEUE, False, False, ""),
            ]:
                self.assertEqual(
                    bool(expression(start["if"], event, ref)), expected_start
                )
                self.assertEqual(
                    bool(expression(completion["if"], event, ref)), expected_complete
                )
                self.assertEqual(expression(phase, event, ref), expected_phase)

    def invoke(self, activity, fail=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            receipt = root / "calls.jsonl"
            gh = root / "gh"
            gh.write_text(
                f"#!{sys.executable}\nimport json,os,sys\n"
                "with open(os.environ['RECEIPT'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n"
                + ("sys.exit(1)\n" if fail else "")
            )
            gh.chmod(0o755)
            sleeper = root / "sleep"
            sleeper.write_text(f"#!{sys.executable}\n")
            sleeper.chmod(0o755)
            result = subprocess.run(
                ["bash", "-e", "-c", self.action["runs"]["steps"][0]["run"]],
                env={
                    **os.environ,
                    "PATH": f"{root}:{os.environ['PATH']}",
                    "RECEIPT": str(receipt),
                    "DEFAULT_BRANCH": "main",
                    "GITHUB_RUN_ID": "123",
                    "GITHUB_RUN_ATTEMPT": "2",
                    "SOURCE_ACTIVITY": activity,
                },
                capture_output=True,
                text=True,
                check=False,
            )
            calls = (
                [json.loads(line) for line in receipt.read_text().splitlines()]
                if receipt.exists()
                else []
            )
            return result, calls

    def test_actual_pinned_bash_consumes_caller_phases(self):
        for workflow in self.workflows.values():
            jobs = workflow["jobs"]
            for phase in [
                jobs["source-start"]["steps"][0]["with"]["source-activity"],
                expression(
                    jobs["queue-completion"]["steps"][0]["with"]["source-activity"]
                ),
                expression(
                    jobs["queue-completion"]["steps"][0]["with"]["source-activity"],
                    ref=QUEUE,
                ),
            ]:
                result, calls = self.invoke(phase)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = [
                    "workflow",
                    "run",
                    "reconcile-merge-queue.yml",
                    "--ref",
                    "main",
                    "-f",
                    "source_run_id=123",
                ]
                if phase:
                    expected += [
                        "-f",
                        "source_run_attempt=2",
                        "-f",
                        f"source_activity={phase}",
                    ]
                self.assertEqual(calls, [expected])

    def test_failed_notification_is_bounded_and_visible(self):
        result, calls = self.invoke("in_progress", fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 3)
        self.assertIn("::warning::", result.stdout + result.stderr)

    def test_failed_completion_is_blocking_only_for_source_producers(self):
        for workflow in self.workflows.values():
            completion = workflow["jobs"]["queue-completion"]
            policy = completion["continue-on-error"]
            phase = completion["steps"][0]["with"]["source-activity"]
            for ref, ignored in [(SOURCE, False), (QUEUE, True)]:
                with self.subTest(ref=ref):
                    self.assertTrue(expression(completion["if"], ref=ref))
                    result, calls = self.invoke(expression(phase, ref=ref), fail=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(len(calls), 3)
                    self.assertIn("::warning::", result.stdout + result.stderr)
                    self.assertIs(expression(policy, ref=ref), ignored)

    def test_actual_collector_ignores_skipped_start_without_waiving_real_jobs(self):
        checks = json.loads(
            self.reconciler["jobs"]["reconcile"]["steps"][0]["with"][
                "package-source-checks"
            ]
        )
        sha = "a" * 40
        runs: list[dict[str, Any]] = []
        jobs: dict[int, list[dict[str, Any]]] = {}
        for index, (workflow, contexts) in enumerate(checks.items(), 1):
            runs.append({
                "id": index,
                "event": "workflow_dispatch",
                "queue_workflow": workflow,
                "head_sha": sha,
                "run_attempt": 1,
                "status": "completed",
                "conclusion": "success",
            })
            jobs[index] = [
                {
                    "id": index * 100 + position,
                    "name": name,
                    "head_sha": sha,
                    "run_id": index,
                    "run_attempt": 1,
                    "status": "completed",
                    "conclusion": "success",
                    "html_url": f"https://github.com/nix-forge/example/actions/runs/{index}/job/{index * 100 + position}",
                }
                for position, name in enumerate(contexts, 1)
            ]
            for callback in [
                "Source validation start callback",
                "Queue completion callback",
            ]:
                jobs[index].append({
                    **jobs[index][0],
                    "name": callback,
                    "conclusion": "skipped",
                })
        published = []

        def api(path, method="GET", data=None):
            if method == "POST":
                self.assertEqual(path, f"repos/nix-forge/example/statuses/{sha}")
                published.append(data)
                return None
            if "/status?" in path:
                return {"statuses": []}
            if "/git/ref/" in path:
                return {"object": {"sha": sha}}
            for run in runs:
                if f"/actions/runs/{run['id']}/jobs?" in path:
                    return {"jobs": jobs[run["id"]]}
                if f"/actions/workflows/{run['queue_workflow']}/runs?" in path:
                    return {"workflow_runs": [run]}
            raise AssertionError(path)

        with (
            patch.multiple(self.queue, SOURCE_CHECKS=checks),
            patch.object(self.queue, "api", side_effect=api),
        ):
            self.assertTrue(self.queue.publish_dispatch_results(QUEUE, sha, runs))
            self.assertEqual(len(published), 16)
            self.assertTrue(all(value["state"] == "success" for value in published))
            published.clear()
            runs[0]["conclusion"] = "failure"
            jobs[1][0]["conclusion"] = "failure"
            self.assertFalse(self.queue.publish_dispatch_results(QUEUE, sha, runs))
            self.assertEqual(len(published), 1)
            self.assertEqual(published[0]["state"], "failure")
            self.assertEqual(published[0]["target_url"], jobs[1][0]["html_url"])


if __name__ == "__main__":
    unittest.main()
