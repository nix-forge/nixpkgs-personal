# shellcheck shell=bash
runHook preCheck
python3 @check_fonts_py@ .
runHook postCheck
