import pathlib
import sys

counter = pathlib.Path(sys.argv[1])
attempt = int(counter.read_text(encoding="utf-8")) + 1 if counter.exists() else 1
counter.write_text(str(attempt), encoding="utf-8")
print(sys.argv[2])  # ruff: ignore[print] -- Emulates build output.
sys.exit(23 if attempt <= int(sys.argv[3]) else 0)
