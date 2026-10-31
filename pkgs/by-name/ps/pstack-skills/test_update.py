"""Distinguish GitHub API failures without publishing arbitrary response data."""

import io
import json
import os
import runpy
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import date
from email.message import Message
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.error import HTTPError

import skills_updater


class GitHubErrorTests(unittest.TestCase):
    def failure(self, message, remaining="0", retry_after="60"):
        headers = Message()
        headers["X-RateLimit-Remaining"] = remaining
        headers["Retry-After"] = retry_after
        error = HTTPError(
            "https://api.github.com/repos/example/skills/commits/main",
            403,
            "Forbidden",
            headers,
            io.BytesIO(json.dumps({"message": message}).encode()),
        )
        output = io.StringIO()
        with (
            patch.object(skills_updater, "urlopen", side_effect=error),
            redirect_stderr(output),
            self.assertRaises(SystemExit) as raised,
        ):
            skills_updater._fetch_latest_commit("example", "skills")
        self.assertEqual(raised.exception.code, 1)
        return output.getvalue()

    def test_rate_limit_failure_includes_safe_retry_metadata(self):
        output = self.failure("API rate limit exceeded for private-address")
        self.assertIn("GitHub API rate limit exceeded", output)
        self.assertIn("X-RateLimit-Remaining=0", output)
        self.assertIn("Retry-After=60", output)
        self.assertNotIn("private-address", output)

    def test_permission_failure_stays_distinct_from_rate_limit(self):
        output = self.failure("Resource not accessible by integration", remaining="99")
        self.assertIn("Resource not accessible by integration", output)
        self.assertIn("X-RateLimit-Remaining=99", output)
        self.assertNotIn("rate limit exceeded", output)

    def test_unrecognized_response_and_headers_are_not_published(self):
        output = self.failure(
            "private response", remaining="private", retry_after="private"
        )
        self.assertIn("HTTP 403", output)
        self.assertNotIn("private", output)


class PublicGitTests(unittest.TestCase):
    def test_public_metadata_is_blobless_and_isolated_from_credentials(self):
        real_run = subprocess.run
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "remote"
            repository.mkdir()
            environment = dict(os.environ)
            environment.update(
                GIT_CONFIG_GLOBAL=os.devnull,
                GIT_CONFIG_NOSYSTEM="1",
                GIT_AUTHOR_NAME="Example",
                GIT_AUTHOR_EMAIL="example@example.invalid",
                GIT_AUTHOR_DATE="2026-10-31T23:50:00-07:00",
                GIT_COMMITTER_NAME="Example",
                GIT_COMMITTER_EMAIL="example@example.invalid",
                GIT_COMMITTER_DATE="2024-01-01T00:00:00Z",
            )

            def git(*arguments):
                return real_run(
                    ["git", "-C", str(repository), *arguments],
                    check=True,
                    capture_output=True,
                    text=True,
                    env=environment,
                ).stdout.strip()

            git("init", "--quiet", "--initial-branch=main")
            git("config", "uploadpack.allowFilter", "true")
            (repository / "blob").write_text("fixture content\n" * 4096)
            git("add", "blob")
            git("commit", "--quiet", "--no-gpg-sign", "-m", "fixture")
            expected_revision = git("rev-parse", "HEAD")
            observed_types = []

            def offline_run(arguments, **kwargs):
                actual = list(arguments)
                child_environment = kwargs["env"]
                self.assertNotIn("GH_TOKEN", child_environment)
                self.assertNotIn("GITHUB_TOKEN", child_environment)
                self.assertNotIn("GIT_DIR", child_environment)
                self.assertNotIn("GIT_CONFIG_COUNT", child_environment)
                self.assertEqual(child_environment["GIT_CONFIG_GLOBAL"], os.devnull)
                self.assertEqual(child_environment["GIT_CONFIG_NOSYSTEM"], "1")
                self.assertEqual(child_environment["GIT_TERMINAL_PROMPT"], "0")
                self.assertEqual(child_environment["HOME"], actual[2])
                if "fetch" in actual:
                    target = actual.index("https://github.com/example/skills.git")
                    actual[target] = repository.as_uri()
                result = real_run(actual, **kwargs)
                if "show" in actual:
                    objects = real_run(
                        [
                            "git",
                            "-C",
                            actual[2],
                            "cat-file",
                            "--batch-all-objects",
                            "--batch-check=%(objecttype)",
                        ],
                        check=True,
                        capture_output=True,
                        text=True,
                        env={**child_environment, "GIT_NO_LAZY_FETCH": "1"},
                    )
                    observed_types.extend(objects.stdout.splitlines())
                return result

            with (
                patch.dict(
                    os.environ,
                    {
                        "GH_TOKEN": "fixture-token",
                        "GITHUB_TOKEN": "fixture-token",
                        "GIT_DIR": str(Path(directory) / "wrong-repository"),
                        "GIT_CONFIG_COUNT": "1",
                        "GIT_CONFIG_KEY_0": "http.extraHeader",
                        "GIT_CONFIG_VALUE_0": "fixture-header",
                    },
                ),
                patch.object(skills_updater.subprocess, "run", side_effect=offline_run),
            ):
                revision, authored = skills_updater._fetch_public_git_commit(
                    "example", "skills"
                )
            self.assertEqual(revision, expected_revision)
            self.assertEqual(authored, date(2026, 11, 1))
            self.assertIn("commit", observed_types)
            self.assertIn("tree", observed_types)
            self.assertNotIn("blob", observed_types)

    def test_invalid_metadata_is_rejected(self):
        for metadata in (
            "invalid\n2026-10-31T00:00:00Z\n",
            "a" * 40 + "\ninvalid\n",
            "a" * 40 + "\n2026-10-31T00:00:00\n",
        ):
            with (
                self.subTest(metadata=metadata),
                patch.object(
                    skills_updater.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], 0, metadata, ""),
                ),
                redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                skills_updater._fetch_public_git_commit("example", "skills")

    def test_git_failures_do_not_publish_subprocess_output(self):
        failures = (
            subprocess.CompletedProcess([], 1, "private-output", "private-error"),
            OSError("private-path"),
            subprocess.TimeoutExpired("private-command", 120),
        )
        for failure in failures:
            output = io.StringIO()
            replacement = (
                Mock(side_effect=failure)
                if isinstance(failure, Exception)
                else Mock(return_value=failure)
            )
            with (
                self.subTest(failure=type(failure).__name__),
                patch.object(skills_updater.subprocess, "run", replacement),
                redirect_stderr(output),
                self.assertRaises(SystemExit),
            ):
                skills_updater._fetch_public_git_commit("example", "skills")
            self.assertNotIn("private", output.getvalue())

    def test_api_transport_remains_default(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            revision = "a" * 40
            authored = date(2026, 10, 31)
            content_hash = "sha256-fixture"
            (package / "source.nix").write_text(
                skills_updater._render_source(
                    "example", "skills", revision, content_hash, authored
                )
            )
            for public_git in (False, True):
                with (
                    self.subTest(public_git=public_git),
                    patch.object(
                        skills_updater,
                        "_fetch_latest_commit",
                        return_value=(revision, authored),
                    ) as api,
                    patch.object(
                        skills_updater,
                        "_fetch_public_git_commit",
                        return_value=(revision, authored),
                    ) as git,
                    patch.object(
                        skills_updater, "_prefetch_source", return_value=content_hash
                    ),
                    redirect_stdout(io.StringIO()),
                ):
                    self.assertEqual(
                        skills_updater.main(
                            "example", "skills", package, [], public_git=public_git
                        ),
                        0,
                    )
                    self.assertEqual(git.call_count, int(public_git))
                    self.assertEqual(api.call_count, int(not public_git))

    def test_pstack_driver_selects_public_git(self):
        with (
            patch.object(skills_updater, "main", return_value=0) as main,
            self.assertRaises(SystemExit),
        ):
            runpy.run_path(
                str(Path(__file__).with_name("update.py")), run_name="__main__"
            )
        self.assertEqual(main.call_args.kwargs, {"public_git": True})


if __name__ == "__main__":
    unittest.main()
