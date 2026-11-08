"""Validate generated artifacts in an isolated build or VM fixture."""

import csv
import pathlib
import zipfile

assert zipfile.is_zipfile("workbook.xlsx")
with pathlib.Path("roundtrip.csv").open(newline="", encoding="utf-8") as stream:
    assert list(csv.reader(stream)) == [["item", "amount"], ["pens", "6"]]
