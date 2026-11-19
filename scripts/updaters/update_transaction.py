"""Publish a prepared package update with rollback on ordinary failures."""

from __future__ import annotations

import difflib
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Mapping


def _stage(path: Path, content: bytes, mode: int) -> Path:
    descriptor, filename = tempfile.mkstemp(
        prefix=f".{path.name}.update-", dir=path.parent
    )
    staged = Path(filename)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        staged.chmod(mode)
    except BaseException:
        staged.unlink(missing_ok=True)
        raise
    return staged


def _snapshot(path: Path) -> tuple[bytes | None, int]:
    if path.is_symlink():
        raise ValueError(f"Update target must not be a symlink: {path}")
    if not path.exists():
        return None, 0o644
    return path.read_bytes(), stat.S_IMODE(path.stat().st_mode)


def _prepare(changes, originals, staged, backups) -> None:
    for path, content in changes.items():
        original, mode = _snapshot(path)
        originals[path] = (original, mode)
        data = content.encode("utf-8") if isinstance(content, str) else content
        staged[path] = _stage(path, data, mode)
        if original is not None:
            backups[path] = _stage(path, original, mode)


def _publish(originals, staged, attempted) -> None:
    for path, original in originals.items():
        if _snapshot(path) != original:
            raise ValueError(f"Update target changed during preparation: {path}")
    for path, temporary in staged.items():
        # Record the attempted rename first, so an interrupt immediately after a
        # successful rename cannot omit that target from rollback.
        attempted.append(path)
        temporary.replace(path)


def _restore_one(path, originals, backups) -> None:
    if _snapshot(path) == originals[path]:
        return
    if originals[path][0] is None:
        path.unlink(missing_ok=True)
    else:
        backups[path].replace(path)


def _restore(attempted, originals, backups) -> tuple[list[BaseException], set[Path]]:
    failures: list[BaseException] = []
    retained: set[Path] = set()
    for path in reversed(attempted):
        try:
            _restore_one(path, originals, backups)
        except BaseException as rollback_error:  # ruff: ignore[blind-except]
            # Preserve recovery data even for a second interruption during rollback.
            if path in backups:
                retained.add(backups[path])
            failure = RuntimeError(
                f"Cannot restore {path}; recovery file: {backups.get(path)}"
            )
            failure.__cause__ = rollback_error
            failures.append(failure)
    return failures, retained


def commit_files(changes: Mapping[Path, str | bytes]) -> None:
    """Publish related source and lock files, restoring originals if publication fails.

    Temporary files and rollback copies are unique siblings on the same filesystem.
    Existing modes are preserved. New metadata files use mode 0644. SIGKILL and
    power loss cannot be rolled back by this process.

    Raises:
        BaseExceptionGroup: Publication failed and an original could not be restored.

    """
    originals = {}
    staged = {}
    backups = {}
    attempted = []
    retained: set[Path] = set()
    try:
        _prepare(changes, originals, staged, backups)
        _publish(originals, staged, attempted)
    except BaseException as error:
        failures, retained = _restore(attempted, originals, backups)
        if failures:
            raise BaseExceptionGroup(
                "Package update rollback failed", [error, *failures]
            ) from error
        raise
    finally:
        for temporary in [*staged.values(), *backups.values()]:
            if temporary not in retained:
                temporary.unlink(missing_ok=True)


def preview(changes: Mapping[Path, str | bytes]) -> None:
    """Print the complete proposed textual changes without editing checkout files."""
    for path, content in changes.items():
        previous = path.read_text() if path.exists() else ""
        updated = content.decode("utf-8") if isinstance(content, bytes) else content
        sys.stdout.write(
            "".join(
                difflib.unified_diff(
                    previous.splitlines(keepends=True),
                    updated.splitlines(keepends=True),
                    fromfile=str(path),
                    tofile=str(path),
                )
            )
        )
