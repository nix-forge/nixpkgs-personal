# shellcheck shell=bash
runHook preCheck

build/hm-ocr-capture selftest

runHook postCheck
