# Personal defaults only; the player's saved appearance settings still win.
{ jellyfin-web, lib }:
jellyfin-web.overrideAttrs (old: {
  pname = "jellyfin-web-personal";
  strictDeps = true;
  meta = old.meta // {
    maintainers = [ ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Jellyfin Web with configurable caption rendering";
  };
  passthru = removeAttrs (old.passthru or { }) [ "updateScript" ];
  patches = (old.patches or [ ]) ++ [
    ./jellyfin-caption-controls.patch
    ./jellyfin-caption-rendering.patch
  ];
  postPatch = (old.postPatch or "") + (builtins.readFile ./scripts/post-patch.sh);
})
