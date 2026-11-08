{
  noctalia-greeter,
  mesa,
  lib,
}:
noctalia-greeter.overrideAttrs (old: {
  pname = "noctalia-greeter-personal";
  patches = (old.patches or [ ]) ++ [ ./authentication-ux.patch ];
  doCheck = true;
  # The headless frame-loop test needs an explicit EGL vendor in the sandbox.
  preCheck = (old.preCheck or "") + ''
    export __EGL_VENDOR_LIBRARY_FILENAMES="${mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
  '';
  prePatch = (old.prePatch or "") + (builtins.readFile ./scripts/pre-patch.sh);
  # The upstream release is supplied by Nixpkgs. Review and rebase the UX patch
  # with each update rather than running the unmodified package's updater.
  passthru = removeAttrs (old.passthru or { }) [ "updateScript" ];
  meta = old.meta // {
    maintainers = [ ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Login greeter with keyboard status, clock and confirmed power actions";
  };
})
