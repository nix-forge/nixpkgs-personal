#!/usr/bin/env python3
"""Update the pinned OpenAI curated Agent Skills catalog."""

from __future__ import annotations

from pathlib import Path

from skills_updater import main

if __name__ == "__main__":
    raise SystemExit(main("openai", "skills", Path(__file__).resolve().parent))
