let
  flake = builtins.getFlake ("git+file://" + toString ../..);
in
flake.packages.x86_64-linux.photocraft.overrideAttrs (previous: {
  pname = "photocraft-spool-diagnostic";
  cargoBuildType = "debug";
  cargoCheckType = "debug";
  cargoBuildFlags = [ "-p" "photocraft-engine" "--lib" "--locked" ];
  cargoTestFlags = [
    "-p" "photocraft-engine" "--lib" "--locked"
    "print_cmds::tests::spool_transport_streams_pdf_and_propagates_refusal"
  ];
  buildFeatures = [];
  checkFeatures = [];
  cargoBuildFeatures = [];
  cargoCheckFeatures = [];
  env = previous.env // {
    CARGO_INCREMENTAL = "0";
    CARGO_PROFILE_DEV_DEBUG = "0";
    CARGO_PROFILE_TEST_DEBUG = "0";
  };
  installPhase = ''
    mkdir -p "$out"
    touch "$out/passed"
  '';
  postInstall = "";
  postFixup = "";
  doInstallCheck = false;
  passthru = {};
})
