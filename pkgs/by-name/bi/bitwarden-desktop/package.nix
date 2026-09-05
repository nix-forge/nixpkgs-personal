{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

let
  pname = "bitwarden-desktop";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  strictDeps = true;

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # Generic fixup would mutate Bitwarden's notarized application and replace
  # the stable Developer ID used by Keychain, Touch ID, and native messaging.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications" "$out/bin"
    cp -a Bitwarden.app "$out/Applications/"
    ln -s "$out/Applications/Bitwarden.app/Contents/MacOS/Bitwarden" "$out/bin/bitwarden"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Secure and free password manager for all of your devices";
    homepage = "https://bitwarden.com";
    downloadPage = "https://github.com/bitwarden/clients/releases";
    changelog = "https://github.com/bitwarden/clients/releases/tag/desktop-v${source.version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "bitwarden";
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
