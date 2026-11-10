let
  flake = builtins.getFlake ("git+file://" + toString ../..);
  package = flake.packages.aarch64-linux.wordcraft;
in
package.overrideAttrs (previous: {
  pname = "wordcraft-arm-ui-diagnostic";
  cargoBuildType = "debug";
  cargoCheckType = "debug";
  cargoBuildFlags = [ "-p" "wordcraft-ui-egui" "--lib" "--locked" ];
  cargoTestFlags = [ "-p" "wordcraft-ui-egui" "--lib" "--locked" ];
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
