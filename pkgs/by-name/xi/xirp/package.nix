{
  stdenvNoCC,
  fetchurl,
  unzip,
  file,
  gnugrep,
  lib,
}:

let
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  pname = "xirp";
  inherit (source) version;

  src = fetchurl source.src;
  sourceRoot = ".";

  nativeBuildInputs = [
    unzip
    file
    gnugrep
  ];

  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;
  # Preserve the Electron application exactly as shipped. The Home Manager
  # module signs its copied application bundle after validating this signature.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    test -d ${source.appName}.app
    grep -A1 '<key>CFBundleIdentifier</key>' ${source.appName}.app/Contents/Info.plist | grep -qx '    <string>com.spotify.xirp</string>'
    grep -A1 '<key>CFBundleShortVersionString</key>' ${source.appName}.app/Contents/Info.plist | grep -qx "    <string>$version</string>"

    install -d "$out/Applications" "$out/bin"
    cp -a ${source.appName}.app "$out/Applications/"

    ln -s "$out/Applications/${source.appName}.app/Contents/MacOS/${source.appName}" "$out/bin/xirp"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/xirp"
    test -x "$out/Applications/${source.appName}.app/Contents/MacOS/${source.appName}"
    grep -A1 '<key>CFBundleIdentifier</key>' "$out/Applications/${source.appName}.app/Contents/Info.plist" | grep -qx '    <string>com.spotify.xirp</string>'
    grep -A1 '<key>CFBundleShortVersionString</key>' "$out/Applications/${source.appName}.app/Contents/Info.plist" | grep -qx "    <string>$version</string>"
    file -L "$out/bin/xirp" | grep -q 'Mach-O 64-bit arm64 executable'
  '';

  passthru.updateScript = ./update.py;

  meta = {
    description = "Spotify's agentic development environment with institutional memory";
    homepage = "https://xirp.spotify.com/";
    downloadPage = "https://xirp.spotify.com/join-beta";
    changelog = "https://backstage.spotify.com/docs/xirp/changelog.md";
    license = lib.licenses.unfree;
    mainProgram = "xirp";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
