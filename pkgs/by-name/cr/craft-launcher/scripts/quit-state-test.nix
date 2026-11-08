{
  lib,
  stdenv,
  rustPlatform,
  source,
}:
rustPlatform.buildRustPackage {
  pname = "craft-launcher-quit-state";
  version = "0.1.0";
  src = source;
  cargoLock.lockFile = ./quit-state-Cargo.lock;
  strictDeps = true;
  # These upstream tests inject the quit callback; no native app is terminated.
  cargoBuildFlags = [
    "-p"
    "craft-quit"
    "--features"
    "egui"
    "--locked"
  ];
  cargoTestFlags = [
    "-p"
    "craft-quit"
    "--features"
    "egui"
    "--lib"
    "--locked"
  ];
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkType = "debug";
  postPatch = ''
    cmp Cargo.lock ${./quit-state-Cargo.lock}
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    touch "$out/passed"
    runHook postInstall
  '';
  meta = {
    description = "Craft Launcher close, cancellation and minimized-window regressions";
    license = lib.licenses.OR [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = lib.platforms.unix;
  };
}
