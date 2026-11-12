{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  findutils,
  gnused,
}:

let
  pname = "pstack-skills";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation (_finalAttrs: {
  inherit pname;
  inherit (source) version;

  src = fetchFromGitHub source.src;
  nativeBuildInputs = [
    findutils
    gnused
  ];
  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit pname; }}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit pname;
      }
    }
  '';

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Agent skills catalog from pstack";
    homepage = "https://github.com/cursor/plugins/tree/main/pstack";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
