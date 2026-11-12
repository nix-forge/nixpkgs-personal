{
  grimblast,
  lib,
  stdenv,
  stdenvNoCC,
}:
let
  meta = {
    maintainers = [ ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Screenshot utility with freeform region capture";
    homepage = "https://github.com/hyprwm/contrib";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
in
if stdenv.hostPlatform.isLinux then
  grimblast.overrideAttrs (previousAttrs: {
    pname = "grimblast-region";
    strictDeps = true;
    postPatch = (previousAttrs.postPatch or "") + (builtins.readFile ./scripts/post-patch.sh);
    meta = previousAttrs.meta // meta;
  })
else
  # Keep metadata readable without evaluating Grimblast's Linux-only inputs.
  stdenvNoCC.mkDerivation {
    pname = "grimblast-region";
    version = "unsupported";
    strictDeps = true;
    dontUnpack = true;
    installPhase = "false";
    inherit meta;
  }
