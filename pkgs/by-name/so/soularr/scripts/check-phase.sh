# shellcheck shell=bash
runHook preCheck
ruff check --isolated --select F821 soularr.py transfer_ownership.py
PYTHONPATH="$PWD" python @check_transfer_ownership_py@
python @check_shared_client_py@ "$PWD/soularr.py"
runHook postCheck
