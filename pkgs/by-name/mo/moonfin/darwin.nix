{
  callPackage,
  _7zz,
  stdenvNoCC,
  pname,
  lib,
  version,
  src,
  meta,
}:
stdenvNoCC.mkDerivation {
  inherit
    pname
    version
    src
    meta
    ;
  nativeBuildInputs = [ _7zz ];
  strictDeps = true;
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # Keep the upstream signature intact for macOS Gatekeeper and Keychain.
  dontFixup = true;

  unpackPhase = builtins.readFile ./scripts/darwin-unpack-phase.sh;

  installPhase = builtins.readFile ./scripts/darwin-install-phase.sh;

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
}
