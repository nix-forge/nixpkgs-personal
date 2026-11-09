{
  lib,
  stdenv,
  darwin,
  proot,
  rustPlatform,
  fetchgit,
  coreutils,
  replaceVars,
  writeShellScriptBin,
}:
let
  nativeCheckEnvironment = replaceVars ./scripts/native-check-environment.sh { inherit coreutils; };
  nativeCheckCargo = writeShellScriptBin "cargo" (
    lib.replaceStrings
      [ "@coreutils@" "@cargo@" ]
      [ (toString coreutils) (toString rustPlatform.rust.cargo) ]
      (builtins.readFile ./scripts/native-check-cargo.sh)
  );
  nativeCheckTests = writeShellScriptBin "swc-native-verifier-tests" (
    lib.replaceStrings [ "@environment@" ] [ (toString nativeCheckEnvironment) ] (
      builtins.readFile ./scripts/native-check-tests.sh
    )
  );
in
rustPlatform.buildRustPackage {
  pname = "bookorbit-swc-native-verifier";
  version = "1.16.12";
  src = fetchgit {
    url = "https://github.com/swc-project/swc.git";
    rev = "1b2c264916cb664d259113717851275fb6b01620";
    # Hash binds the authoritative verifier, carrier and test fixture subset.
    hash = "sha256-E4ieTEdl0EXhs8CqnSxP2jOsxTVjXzh2mqIbpPUmof0=";
    fetchSubmodules = false;
    nonConeMode = true;
    sparseCheckout = [
      "/crates/swc_native_addon/"
      "/tools/swc-native-addon-pack/"
      "/bindings/binding_native_addon/"
      "/LICENSE"
    ];
  };
  # These three upstream crates use explicit dependency versions and paths.
  # Select only their workspace; preserve every package manifest and Rust file.
  postPatch = ''
    install -m 0644 ${./swc-verifier-workspace.toml} Cargo.toml
    install -m 0644 ${./swc-verifier-Cargo.lock} Cargo.lock
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      # The sandbox cannot execute the host's codesign. Preserve fixture signing
      # through the declared Nix signer, as upstream Nixpkgs does for Node tests.
      substituteInPlace \
        tools/swc-native-addon-pack/tests/verify.rs \
        bindings/binding_native_addon/tests/carrier.rs \
        crates/swc_native_addon/tests/support/mod.rs \
        --replace-fail '"/usr/bin/codesign"' '"${darwin.sigtool}/bin/codesign"'
    ''}
  '';
  cargoLock.lockFile = ./swc-verifier-Cargo.lock;
  cargoBuildFlags = [
    "--locked"
    "-p"
    "swc_native_addon_pack"
  ];
  cargoTestFlags = [
    "--locked"
    "-p"
    "swc_native_addon_pack"
  ];
  # Keep the hook's explicit --target, while nested native fixtures use host layout.
  preCheck = ''
    source ${nativeCheckEnvironment}
    export PATH="${nativeCheckCargo}/bin:$PATH"
  '';
  nativeCheckInputs = lib.optionals stdenv.hostPlatform.isDarwin [ darwin.sigtool ];
  doCheck = true;
  # The strict Linux builder exposes unmapped owner65534 at /. Keep the exact
  # upstream cache validator and invoking UID/GID in a private owned filesystem.
  postCheck =
    if stdenv.hostPlatform.isLinux then
      ''
        source ${
          replaceVars ./scripts/native-check-owned-root.sh {
            inherit proot coreutils;
            nativeCheckCommand = "${nativeCheckTests}/bin/swc-native-verifier-tests";
          }
        }
      ''
    else
      ''
        cargo test --offline --locked -p swc_native_addon --test format --test integrity
      '';
  meta = {
    description = "Upstream SWC native carrier verifier and payload extractor";
    homepage = "https://github.com/swc-project/swc";
    license = lib.licenses.asl20;
    mainProgram = "swc-native-addon-verify";
  };
}
