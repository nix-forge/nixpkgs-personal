"""Guard the public vendor download URL used by the Spotify package."""

from __future__ import annotations

import base64
import importlib.util
import json
import re
import sys
import time
import unittest
from pathlib import Path
from unittest.mock import patch

PACKAGE = Path(__file__).resolve().parents[1] / "pkgs/by-name/sp/spotify-spotx"
sys.path.insert(0, str(PACKAGE))
spec = importlib.util.spec_from_file_location(
    "spotify_spotx_update", PACKAGE / "update.py"
)
assert spec is not None
assert spec.loader is not None
updater = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = updater
spec.loader.exec_module(updater)


def token_expires_at(expiration: int) -> str:
    payload = base64.urlsafe_b64encode(
        json.dumps({"exp": expiration}).encode()
    ).decode()
    return f"header.{payload.rstrip('=')}.signature"


class SpotifyAuthorizationTests(unittest.TestCase):
    def test_rejects_expiring_authorization(self) -> None:
        with patch.object(updater, "time", return_value=1_000_000):
            with self.assertRaises(SystemExit):
                updater._validate_fauth_expiry(token_expires_at(1_000_001))
            updater._validate_fauth_expiry(token_expires_at(2_000_000))

    def test_pinned_url_has_time_to_remain_buildable(self) -> None:
        source = (PACKAGE / "source.nix").read_text()
        match = re.search(r'url = "[^"]+\?fauth=([^"]+)";', source)
        assert match is not None
        updater._validate_fauth_expiry(match.group(1))
        expiration = json.loads(
            base64.urlsafe_b64decode(match.group(1).split(".")[1] + "===")
        )["exp"]
        self.assertGreater(expiration, time.time() + 7 * 24 * 60 * 60)


if __name__ == "__main__":
    unittest.main()
