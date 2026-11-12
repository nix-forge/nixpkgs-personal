#!/usr/bin/env python3
"""Preserve the shared NUR workflow entry point with its pinned runtime."""

import os
import sys
from pathlib import Path

# nix-forge/ci calls this public filename before entering a development shell.
os.execvp(  # ruff: ignore[start-process-with-no-shell] - Fixed argv replaces the launcher and preserves signals.
    "nix",
    [
        "nix",
        "develop",
        ".#nur",
        "--command",
        "python3",
        str(Path(__file__).with_name("check_nur.py")),
        *sys.argv[1:],
    ],
)
