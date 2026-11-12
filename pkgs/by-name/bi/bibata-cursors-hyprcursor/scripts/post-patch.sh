# shellcheck shell=bash
substituteInPlace src/cursor_utils.py \
  --replace-fail \
  'import sys' \
  $'import os\nimport sys' \
  --replace-fail \
  "tmp = Path('/tmp/.cursor.0248.svg')" \
  "tmp = Path(os.environ['TMPDIR']) / f'.cursor.{os.getpid()}.svg'"
