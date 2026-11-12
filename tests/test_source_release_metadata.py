"""Reject invalid or misleading source release metadata before building packages."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "check_source_pins", Path(__file__).with_name("check_source_pins.py")
)
assert SPEC is not None
assert SPEC.loader is not None
PINS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PINS)


class SourceReleaseMetadataTest(unittest.TestCase):
    def test_stable_and_development_releases(self) -> None:
        for kind, version in [("stable", "1.2.3"), ("development", "1.2.3-rc1")]:
            with self.subTest(kind=kind):
                PINS.validate(
                    {
                        "version": version,
                        "releaseDate": "2024-02-29",
                        "releaseType": kind,
                    },
                    "example",
                )

    def test_snapshot_requires_its_pinned_source_date(self) -> None:
        pins = {
            "version": "1.2.3-unstable-2026-10-12",
            "releaseDate": "2026-10-12",
            "releaseType": "snapshot",
        }
        PINS.validate(pins, "example")
        with self.assertRaisesRegex(ValueError, "Snapshot date"):
            PINS.validate({**pins, "releaseDate": "2026-10-11"}, "example")
        with self.assertRaisesRegex(ValueError, "must not be marked stable"):
            PINS.validate({**pins, "releaseType": "stable"}, "example")

    def test_invalid_calendar_dates_and_incomplete_metadata(self) -> None:
        for date in ["2023-02-29", "2026-02-31", "20261012", "2026-13-01"]:
            with self.subTest(date=date), self.assertRaises(ValueError):
                PINS.validate(
                    {"version": "1.2.3", "releaseDate": date, "releaseType": "stable"},
                    "example",
                )
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            PINS.validate({"releaseDate": "2026-10-12"}, "example")

    def test_unknown_release_kind(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unknown"):
            PINS.validate(
                {
                    "version": "1.2.3",
                    "releaseDate": "2026-10-12",
                    "releaseType": "latest",
                },
                "example",
            )

    def test_existing_sources_without_release_fields_remain_valid(self) -> None:
        self.assertEqual(PINS.validate({"version": "1.2.3"}, "example"), 0)


if __name__ == "__main__":
    unittest.main()
