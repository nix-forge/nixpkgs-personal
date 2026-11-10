let
  flake = builtins.getFlake ("git+file://" + toString ../..);
  tools = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  repair = ../../pkgs/by-name/de/designcraft/print-fixture-timestamp.patch;
in
flake.packages.${builtins.currentSystem}.designcraft.overrideAttrs (previous: {
  pname = "designcraft-print-diagnostic";
  cargoBuildType = "debug";
  cargoCheckType = "debug";
  cargoBuildFlags = [ "-p" "designcraft-engine" "--lib" "--locked" ];
  env = previous.env // {
    CARGO_INCREMENTAL = "0";
    CARGO_PROFILE_DEV_DEBUG = "0";
    CARGO_PROFILE_TEST_DEBUG = "0";
    CARGO_TERM_COLOR = "never";
  };
  nativeCheckInputs = (previous.nativeCheckInputs or []) ++ [ tools.patch tools.python3 ];
  checkPhase = ''
    runHook preCheck
    run_engine() {
      cargo test -j "$NIX_BUILD_CORES" --target ${tools.stdenv.hostPlatform.rust.rustcTarget} \
        --offline -p designcraft-engine --lib --locked -- "$@"
    }
    patch -R -p1 --fuzz=0 < ${repair}
    python3 ${./designcraft-print-delay.py} add
    if run_engine cmd::print::tests::print_submits_the_selected_export_and_reports_refusal --exact > baseline.log 2>&1; then
      cat baseline.log
      echo 'Original delayed fixture unexpectedly passed.' >&2
      exit 1
    fi
    grep -F 'test result: FAILED. 0 passed; 1 failed;' baseline.log
    python3 ${./designcraft-print-delay.py} remove
    patch -p1 --fuzz=0 < ${repair}
    python3 ${./designcraft-print-delay.py} add
    run_engine cmd::print::tests::print_submits_the_selected_export_and_reports_refusal --exact
    python3 ${./designcraft-print-delay.py} remove
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
