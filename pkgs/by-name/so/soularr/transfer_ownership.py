"""Recover only transfers claimed by this serialized Soularr worker."""

import contextlib
import json
import os
import uuid
from pathlib import Path


class TransferOwnership:
    def __init__(self, transfers, state_dir, download_dir):
        self.api = transfers
        self.path = Path(state_dir) / "owned-transfers.json"
        self.download_dir = Path(download_dir)
        self.records = json.loads(self.path.read_text()) if self.path.exists() else {}

    @staticmethod
    def key(username: str, filename: str) -> str:
        return username + "\0" + filename

    def save(self):
        temporary = self.path.with_suffix(".tmp")
        with temporary.open("w") as handle:
            json.dump(self.records, handle)
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(self.path)

    def begin(self, username, files, file_dir):
        # Persist intent before enqueue so an accepted request with a lost HTTP
        # response can be recovered after restart.
        for file in files:
            self.records[self.key(username, file["filename"])] = {
                "username": username,
                "filename": file["filename"],
                "file_dir": file_dir,
            }
        self.save()

    def quarantine(self, file):
        parts = [file["file_dir"].split("\\")[-1], file["filename"].split("\\")[-1]]
        if any(part in {"", ".", ".."} or "/" in part for part in parts):
            raise RuntimeError("Unsafe transfer path; files preserved")
        source = self.download_dir.joinpath(*parts)
        if source.exists():
            if source.is_symlink() or not source.resolve().is_relative_to(
                self.download_dir.resolve()
            ):
                raise RuntimeError("Unsafe transfer path; files preserved")
            target = self.download_dir / "failed_downloads" / str(uuid.uuid4())
            target.mkdir(parents=True)
            source.rename(target / source.name)
            # Other consumers may still have files in this shared directory.
            with contextlib.suppress(OSError):
                source.parent.rmdir()

    def finish(self, files, *, quarantine=False):
        for file in files:
            key = self.key(file["username"], file["filename"])
            self.records[key] = {**file, "quarantine": quarantine}
            self.save()
            if not self.api.cancel_download(
                username=file["username"], id=file["id"], remove=True
            ):
                raise RuntimeError(
                    "Could not reconcile owned transfer; retry on restart"
                )
            if quarantine:
                self.quarantine(file)
            self.records.pop(key, None)
            self.save()

    def recover(self):
        if not self.records:
            return
        current = {
            self.key(peer["username"], file["filename"]): file
            for peer in self.api.get_all_downloads()
            for directory in peer.get("directories", [])
            for file in directory.get("files", [])
        }
        for key, record in list(self.records.items()):
            if key in current:
                self.finish([{**record, "id": current[key]["id"]}], quarantine=True)
            else:
                # A saved transfer ID proves ownership even if the process
                # stopped after API removal but before local quarantine.
                if record.get("id") and record.get("quarantine"):
                    self.quarantine(record)
                self.records.pop(key)
                self.save()
