"""Restore only the old inspector while keeping independent regression fixtures."""
import sys
from pathlib import Path

source = Path("crates/engine/src/cmd/fileio/tests_pdf13.rs")
text = source.read_text()
start = text.index("fn transparency(")
end = text.index("// Like the writer's PDF/X", start)
original = Path(sys.argv[1]).read_text()
original = original.replace("    let text =", '    let _ = name_values(&pdf_objects(pdf), b"/BM");\n    let text =', 1)
text = text[:start] + original + "\n\n" + text[end:]
needle = "    assert_eq!(transparency(&pdf), Vec::<&str>::new());"
assert text.count(needle) == 1
context = 'pdf.windows(3).enumerate().filter(|(_, bytes)| *bytes == b"/BM").take(8).map(|(at, _)| (at, &pdf[at.saturating_sub(12)..(at + 24).min(pdf.len())])).collect::<Vec<_>>()'
text = text.replace(needle, '    assert_eq!(transparency(&pdf), Vec::<&str>::new(), "/BM contexts: {:?}", ' + context + ');')
source.write_text(text)
