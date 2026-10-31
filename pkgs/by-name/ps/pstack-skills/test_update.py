"""Distinguish GitHub API failures without publishing arbitrary response data."""

import io
import json
import unittest
from contextlib import redirect_stderr
from email.message import Message
from unittest.mock import patch
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


if __name__ == "__main__":
    unittest.main()
