{
  replaceVars,
  replaceVarsWith,
  runtimeShell,
  lib,
  fetchFromGitHub,
  noctalia,
  dbus,
  python3,
}:
let
  source = import ./source.nix;
  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia";
    inherit (source) rev hash;
  };
  testDbusSession = replaceVarsWith {
    name = "dbus-test-session.sh";
    src = ./scripts/dbus-test-session.sh.in;
    isExecutable = true;
    replacements = {
      runtime_shell = runtimeShell;
      dbus_run_session = lib.getExe' dbus "dbus-run-session";
      dbus_daemon = lib.getExe' dbus "dbus-daemon";
      dbus_session_config = "${dbus.out}/share/dbus-1/session.conf";
    };
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
  mesonFlags = lib.unique (
    lib.remove "-Dtests=disabled" (old.mesonFlags or [ ]) ++ [ "-Dtests=enabled" ]
  );
  postPatch = (old.postPatch or "") + ''
    substituteInPlace meson.build \
      --replace-fail "dbus_run_session = find_program('dbus-run-session', required: false)" \
      "dbus_run_session = find_program('${testDbusSession}', required: true)"
    source ${
      replaceVars ./scripts/post-patch.sh {
        source_version = source.version;
        source_revision = source.rev;
        bar_icon_policy_h = "${./bar_icon_policy.h}";
      }
    }
  '';
  doCheck = true;
  nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [
    dbus
    python3
  ];
  checkPhase = ''
    source ${
      replaceVars ./scripts/check-phase.sh {
        test_inventory_python = "${./check_test_inventory.py}";
        test_bar_icon_policy_cpp = "${./test_bar_icon_policy.cpp}";
        test_route_preference_cpp = "${./test_route_preference.cpp}";
      }
    }
  '';
  postInstall = (old.postInstall or "") + ''
    source ${replaceVars ./scripts/post-install.sh { readme = "${./README.md}"; }}
  '';
  passthru = removeAttrs (old.passthru or { }) [ "updateScript" ] // {
    upstreamRevision = source.rev;
    inherit testDbusSession;
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
