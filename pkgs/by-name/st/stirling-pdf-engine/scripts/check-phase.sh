# shellcheck shell=bash
runHook preCheck
export HOME="$TMPDIR"
export STIRLING_ENGINE_DATA_DIR="$TMPDIR/state"
export PYTHONPATH="$PWD/src:$PYTHONPATH"
python -m pytest tests/test_engine_auth.py tests/test_config_cache.py \
  tests/test_documents.py tests/test_stirling_api.py
runHook postCheck
