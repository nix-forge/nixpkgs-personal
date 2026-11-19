{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  findutils,
  gawk,
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
    gawk
  ];
  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit pname; }}
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
