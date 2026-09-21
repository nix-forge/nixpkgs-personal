"""Fuzz path containment for imported Apple font payloads."""

import importlib.util
import sys
import tempfile
from pathlib import Path

import atheris

MAX_INPUT_SIZE = 1024

SCRIPT = (
    Path(__file__).resolve().parents[1] / "pkgs/by-name/ap/apple-fonts/font_support.py"
)
with atheris.instrument_imports():
    spec = importlib.util.spec_from_file_location("apple_font_support", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    support = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(support)
    atheris.instrument_func(support.safe_path)

directory = tempfile.TemporaryDirectory(prefix="font-path-fuzz-")
base = Path(directory.name)
root = base / "payload"
root.mkdir()
(base / "outside").mkdir()
(root / "escape").symlink_to(base / "outside", target_is_directory=True)


def check(name: str) -> None:
    try:
        path = support.safe_path(root, name)
    except ValueError:
        return
    assert path == root / name
    assert path.resolve().is_relative_to(root.resolve())
    assert ".." not in Path(name).parts
    assert not Path(name).is_absolute()


@atheris.instrument_func
def test_one_input(data: bytes) -> None:
    if len(data) > MAX_INPUT_SIZE:
        return
    name = data.decode("utf-8", errors="replace")
    for candidate in (name, f"../{name}", f"/{name}", f"escape/{name}"):
        check(candidate)


if __name__ == "__main__":
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
