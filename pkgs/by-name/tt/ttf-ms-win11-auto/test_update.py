"""Exercise Microsoft ISO alias lag without contacting its download service."""

from __future__ import annotations

import unittest
from typing import Self
from unittest.mock import patch

import update


class _Response:
    def __init__(self, url: str) -> None:
        self.url = url

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def geturl(self) -> str:
        return self.url


class AliasTests(unittest.TestCase):
    def test_unpublished_alias_keeps_existing_verified_pin(self) -> None:
        redirect = "https://www.bing.com/?ref=aka&shorturl=Win11E-ISO-26H2-en-us"
        existing = update._UpstreamState(
            "10.0.26200.6584", "https://example.com/old.iso", "sha256-old"
        )
        with (
            patch.object(update, "_fetch_text", return_value="Windows 11 version 26H2"),
            patch.object(update, "urlopen", return_value=_Response(redirect)),
            patch.object(update, "_prefetch_iso_hash") as prefetch,
        ):
            self.assertEqual(
                update._discover_upstream(
                    "https://example.com", existing_source=existing
                ),
                existing,
            )
        prefetch.assert_not_called()

    def test_unpublished_alias_requires_existing_pin(self) -> None:
        redirect = "https://www.bing.com/?ref=aka&shorturl=Win11E-ISO-26H2-en-us"
        with (
            patch.object(update, "_fetch_text", return_value="Windows 11 version 26H2"),
            patch.object(update, "urlopen", return_value=_Response(redirect)),
            self.assertRaises(SystemExit),
        ):
            update._discover_upstream("https://example.com")

    def test_unexpected_redirect_remains_an_error(self) -> None:
        with (
            patch.object(
                update,
                "urlopen",
                return_value=_Response("https://example.com/not-an-iso"),
            ),
            self.assertRaises(SystemExit),
        ):
            update._resolve_iso_url("https://aka.ms/Win11E-ISO-26H2-en-us")


if __name__ == "__main__":
    unittest.main()
