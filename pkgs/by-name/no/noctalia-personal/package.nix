{
  replaceVars,
  lib,
  fetchFromGitHub,
  noctalia,
}:
let
  source = import ./source.nix;
  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia";
    inherit (source) rev hash;
  };
  upstream = noctalia.overrideAttrs (_: {
    inherit src;
    inherit (source) version;
  });
in
upstream.overrideAttrs (old: {
  strictDeps = true;
  pname = "noctalia-personal";
  patches = (old.patches or [ ]) ++ [
    ./symbolic-bar-icons.patch
    ./media-player-selector.patch
    ./audio-application-id.patch
    # Semantic secondary text already carries the palette's contrast hierarchy.
    ./readable-control-colors.patch
    # Minimal inline workspace groups share target sizes and a quiet state hierarchy.
    ./workspace-strip.patch
    ./preferred-wired-uplink.patch
  ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];
  postPatch = (old.postPatch or "") + ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        source_version = source.version;
        source_revision = source.rev;
        bar_icon_policy_h = "${./bar_icon_policy.h}";
      }
    }
  '';
  postInstall = (old.postInstall or "") + ''
    source ${replaceVars ./scripts/post-install.sh { readme = "${./README.md}"; }}
  '';
  passthru = removeAttrs (old.passthru or { }) [ "updateScript" ] // {
    upstreamRevision = source.rev;
  };
  meta = old.meta // {
    maintainers = [ ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    license = with lib.licenses; [
      mit
      asl20
    ];
    description = "Desktop shell with themed icons, readable controls and landscape media playback";
  };
})
