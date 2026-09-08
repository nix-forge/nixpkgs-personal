{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "t3-code";
  appName = "T3 Code (Alpha)";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;
  dontBuild = true;
  dontConfigure = true;
  # The official bundle is signed and notarized. Generic fixup would mutate
  # its contents and invalidate that identity without improving Darwin runtime
  # compatibility.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications" "$out/bin"
    cp -a "${appName}.app" "$out/Applications/"
    ln -s "$out/Applications/${appName}.app/Contents/MacOS/${appName}" "$out/bin/${pname}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s "$out/Applications/T3 Code (Alpha).app/Contents/Info.plist"
    test -x "$out/Applications/T3 Code (Alpha).app/Contents/MacOS/T3 Code (Alpha)"
    test -x "$out/bin/t3-code"
    runHook postInstallCheck
  '';

  passthru.updateScript = [
    "python3"
    "pkgs/by-name/t3/t3-code/update.py"
  ];

  meta = {
    description = "Desktop control surface for AI coding agents";
    homepage = "https://t3.codes/";
    downloadPage = "https://github.com/pingdotgg/t3code/releases";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${source.version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
