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
  pname = "mattpocock-skills";
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
    description = "Matt Pocock's Agent Skills catalog";
    homepage = "https://github.com/mattpocock/skills";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
