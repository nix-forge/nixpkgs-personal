"""Validate generated artifacts in an isolated build or VM fixture."""

import json
import pathlib

result = json.loads(pathlib.Path("result.json").read_text(encoding="utf-8"))
assert result == 6, result
