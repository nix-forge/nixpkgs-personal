{
  replaceVars,
  fetchFromGitHub,
  jq,
  lib,
  pkgsCross,
  stdenvNoCC,
  unzip,
  zip,
}:
let
  source = import ./source.nix;
  upstreamSource = fetchFromGitHub {
    owner = "J0R6IT0";
    repo = "navidrome-lyrics-plugin";
    tag = "v${source.version}";
    inherit (source) hash;
  };
  # Navidrome loads WASI plugins on every supported host architecture.
  wasm = pkgsCross.wasm32-wasip1.rustPlatform.buildRustPackage {
    pname = "nd-lyrics-wasm";
    inherit (source) version;
    src = upstreamSource;
    inherit (source) cargoHash;
    strictDeps = true;
    # Nixpkgs' WASI cross compiler currently selects clang as the linker, but
    # rustc passes wasm-ld flags directly for cdylib outputs.
    nativeBuildInputs = [ pkgsCross.wasm32-wasip1.lld ];
    env.RUSTFLAGS = "-C linker=wasm-ld";
    doCheck = false; # The WASI target cannot run Rust unit tests on the build host.
    installPhase = builtins.readFile ./scripts/install-wasm-plugin.sh;
  };
in
stdenvNoCC.mkDerivation {
  pname = "nd-lyrics";
  inherit (source) version;
  src = upstreamSource;
  strictDeps = true;
  nativeBuildInputs = [ zip ];
  nativeInstallCheckInputs = [
    jq
    unzip
  ];
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit wasm; }}
  '';
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;
  passthru.isNavidromePlugin = true;
  meta = {
    description = "Multi-source synchronized lyrics plugin for Navidrome";
    homepage = "https://github.com/J0R6IT0/navidrome-lyrics-plugin";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = lib.platforms.all;
  };
}
