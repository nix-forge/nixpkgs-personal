{
  lib,
  stdenv,
  swift,
  src,
}:
stdenv.mkDerivation {
  pname = "rea-darwin-helpers";
  inherit (import ./source.nix) version;
  inherit src;
  strictDeps = true;
  nativeBuildInputs = [ swift ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    swiftc -O -parse-as-library \
      bridge/process/ProcessRunTokenReader.swift \
      bridge/process/ProcessRunTokenReaderMain.swift -o rea-process-token-reader
    # Swift requires the top-level entry point to be named main.swift.
    ln -s "$PWD/bridge/native/ReaNativeUI.swift" main.swift
    swiftc -O bridge/native/NativeUIChildren.swift \
      bridge/native/NativeUIValues.swift main.swift -o rea-native-ui
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 rea-process-token-reader "$out/bin/rea-process-token-reader"
    install -Dm755 rea-native-ui "$out/bin/rea-native-ui"
    runHook postInstall
  '';
  meta = {
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
