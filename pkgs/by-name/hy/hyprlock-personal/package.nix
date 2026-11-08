{
  replaceVars,
  lib,
  fetchFromGitHub,
  hyprlock,
  wayland-scanner,
}:
let
  source = import ./source.nix;
in
hyprlock.overrideAttrs (old: {
  pname = "hyprlock-personal";
  inherit (source) version;
  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprlock";
    inherit (source) rev hash;
  };
  strictDeps = true;
  # Failed lock acquisition must dispose of GL objects before exit callbacks
  # tear down the vendor context, just as normal authenticated unlock does.
  patches = (old.patches or [ ]) ++ [
    ./authentication-controls.patch
    ./ordered-graphics-cleanup.patch
  ];
  # The scanner is a build tool. With strict dependency separation its .pc
  # file is absent from the target pkg-config path; pass its protocol data
  # explicitly instead of relying on leaked native build inputs.
  postPatch = (old.postPatch or "") + ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        waylandScanner = lib.getOutput "out" wayland-scanner;
      }
    }
  '';
  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
    (lib.cmakeFeature "HYPRLOCK_COMMIT" (builtins.substring 0 7 source.rev))
    (lib.cmakeFeature "HYPRLOCK_VERSION_COMMIT" "")
  ];
  # This composition retains the upstream PAM termination fix. Review source
  # changes and the native submit guards together, with an isolated lock test.
  passthru = removeAttrs (old.passthru or { }) [ "updateScript" ];
  meta = old.meta // {
    maintainers = [ ];
    description = "Hyprlock with native password submission and aligned authentication controls";
    changelog = "https://github.com/hyprwm/hyprlock/commits/${source.rev}/";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
