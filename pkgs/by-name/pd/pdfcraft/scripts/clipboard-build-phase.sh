# shellcheck shell=bash
# shellcheck disable=SC2154
runHook preBuild
export CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
# The regression is a library unit test. --lib deliberately excludes unrelated
# UI integration tests; --no-run never executes compositor-dependent tests here.
cargo test --no-run --locked --offline --lib -p pdfcraft-ui-egui \
  --features=eframe/wayland,eframe/x11 \
  --target @rust_target@ \
  --jobs "$NIX_BUILD_CORES" --message-format=json >clipboard-build.json
python3 @artifact_selector@ clipboard-build.json clipboard-test-path
runHook postBuild
