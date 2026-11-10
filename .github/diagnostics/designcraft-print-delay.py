"""Force a wall-clock boundary between the fixture's two PDF exports."""
import sys
from pathlib import Path

source = Path("crates/engine/src/cmd/print.rs")
text = source.read_text()
marker = "        std::thread::sleep(std::time::Duration::from_secs(2));\n"
if sys.argv[1] == "add":
    needle = "        let r = print_with(&mut s, &params,"
    if text.count(needle) != 1 or marker in text:
        raise RuntimeError("Unexpected print fixture source")
    text = text.replace(needle, marker + needle)
elif sys.argv[1] == "remove":
    if text.count(marker) != 1:
        raise RuntimeError("Missing controlled delay")
    text = text.replace(marker, "")
else:
    raise ValueError("Choose add or remove")
source.write_text(text)
