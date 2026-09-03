{
  lib,
  stdenv,
  rustPlatform,
  rustfmt,
  clippy,
  cargo-deny,
  cargo-machete,
  coreutils,
  curl,
  libiconv,
  wireguard-tools,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.lock
      ./Cargo.toml
      ./README.md
      ./deny.toml
      ./rustfmt.toml
      ./src
    ];
  };
in
rustPlatform.buildRustPackage {
  pname = "wireguard-roaming-controller";
  version = "0.2.0";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";
  strictDeps = true;

  env = {
    WIREGUARD_ROAMING_CURL = lib.getExe curl;
    WIREGUARD_ROAMING_WG = lib.getExe' wireguard-tools "wg";
    WIREGUARD_ROAMING_WG_QUICK = lib.getExe' wireguard-tools "wg-quick";
    WIREGUARD_ROAMING_PATH = lib.makeBinPath [ wireguard-tools ];
    WIREGUARD_ROAMING_TEST_FALSE = lib.getExe' coreutils "false";
    WIREGUARD_ROAMING_TEST_PRINTF = lib.getExe' coreutils "printf";
    WIREGUARD_ROAMING_TEST_SLEEP = lib.getExe' coreutils "sleep";
  };

  nativeCheckInputs = [
    cargo-deny
    cargo-machete
    clippy
    rustfmt
  ];
  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    cargo fmt --all -- --check
    cargo check --all-targets --all-features --locked --profile release
    cargo clippy --all-targets --all-features --locked --profile release -- -D warnings
    cargo test --all-targets --all-features --locked --profile release --no-fail-fast
    RUSTDOCFLAGS=-Dwarnings cargo doc --no-deps --document-private-items --locked --profile release
    cargo machete .
    cargo deny --locked check bans licenses sources

    runHook postCheck
  '';

  meta = {
    description = "Standalone WireGuard controller for nix-darwin";
    homepage = "https://github.com/nix-forge/nixpkgs-personal";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "wireguard-roaming-controller";
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
