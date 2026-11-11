let
  flake = builtins.getFlake ("git+file://" + toString ../..);
  tools = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
in
flake.packages.${builtins.currentSystem}.vectorcraft.overrideAttrs (previous: {
  pname = "vectorcraft-pdf13-diagnostic";
  cargoBuildType = "debug";
  cargoCheckType = "debug";
  cargoBuildFlags = [ "-p" "vectorcraft-engine" "--lib" "--locked" ];
  env = previous.env // {
    CARGO_INCREMENTAL = "0";
    CARGO_PROFILE_DEV_DEBUG = "0";
    CARGO_PROFILE_TEST_DEBUG = "0";
    CARGO_TERM_COLOR = "never";
  };
  checkPhase = ''
    runHook preCheck
    run_engine() {
      cargo test -j "$NIX_BUILD_CORES" --target ${tools.stdenv.hostPlatform.rust.rustcTarget} \
        --offline -p vectorcraft-engine --lib --locked -- "$@"
    }
    cp crates/engine/src/cmd/fileio/tests_pdf13.rs "$TMPDIR/fixed-tests.rs"
    python3 ${./vectorcraft-pdf13-baseline.py} ${./vectorcraft-old-inspector.rs}
    if run_engine cmd::fileio::tests_pdf13::transparency_inspection_ignores_binary_image_data --exact > baseline.log 2>&1; then
      cat baseline.log
      echo 'Old raw inspector unexpectedly accepted the binary fixture.' >&2
      exit 1
    fi
    grep -F 'test result: FAILED. 0 passed; 1 failed;' baseline.log
    if run_engine cmd::fileio::tests_pdf13::pdf_1_3_flattens_all_transparency_and_looks_the_same --exact > export-context.log 2>&1; then
      cat export-context.log
    else
      grep -F '/BM contexts:' export-context.log
      grep -F 'test result: FAILED. 0 passed; 1 failed;' export-context.log
    fi
    cp "$TMPDIR/fixed-tests.rs" crates/engine/src/cmd/fileio/tests_pdf13.rs
    run_engine cmd::fileio::tests_pdf13
    run_engine
    runHook postCheck
  '';
  installPhase = ''
    mkdir -p "$out"
    touch "$out/passed"
  '';
  postInstall = "";
  postFixup = "";
  doInstallCheck = false;
  passthru = {};
})
