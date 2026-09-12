{ noctalia-greeter }:
noctalia-greeter.overrideAttrs (old: {
  pname = "noctalia-greeter-personal";
  patches = (old.patches or [ ]) ++ [ ./authentication-ux.patch ];
  doCheck = true;
  prePatch = (old.prePatch or "") + ''
    if [ "$version" != 1.3.1 ]; then
      echo "Review the authentication UX patch for noctalia-greeter $version" >&2
      exit 1
    fi
  '';
  # The upstream release is supplied by Nixpkgs. Review and rebase the UX patch
  # with each update rather than running the unmodified package's updater.
  passthru = removeAttrs (old.passthru or { }) [ "updateScript" ];
  meta = old.meta // {
    description = "Noctalia greeter with keyboard status, clock, and confirmed power actions";
  };
})
