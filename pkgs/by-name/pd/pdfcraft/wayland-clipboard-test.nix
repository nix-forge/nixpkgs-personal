# Native image clipboard regression under an isolated Linux compositor.
{
  replaceVars,
  lib,
  stdenv,
  runCommand,
  python3,
  sway,
  wl-clipboard,
  wayland-utils,
  dbus,
  fontconfig,
  package,
  runtimeLibraries,
  fonts,
  ocrModels,
  runner,
  runnerTests,
  fixture,
}:
assert lib.assertMsg stdenv.hostPlatform.isLinux "Native clipboard protocol check requires Linux";
let
  artifact = package.overrideAttrs (old: {
    name = "pdfcraft-native-clipboard-test-${package.version}";
    pname = "pdfcraft-native-clipboard-test";
    inherit (package) src cargoDeps;
    passthru = { };
    cargoBuildType = "debug";
    doCheck = false;
    doInstallCheck = false;
    dontStrip = true;
    preCheck = "";
    postCheck = "";
    preInstall = "";
    postInstall = "";
    installCheckPhase = "";
    postFixup = "";
    buildPhase = ''
      source ${
        replaceVars ./scripts/clipboard-build-phase.sh {
          rust_target = lib.escapeShellArg stdenv.hostPlatform.rust.rustcTarget;
          artifact_selector = lib.escapeShellArg "${./scripts/select_clipboard_artifact.py}";
        }
      }
    '';
    installPhase = ''
      source ${
        replaceVars ./scripts/clipboard-install-phase.sh {
          runtime_library_path = lib.escapeShellArg (lib.makeLibraryPath runtimeLibraries);
          fontconfig_path = lib.escapeShellArg (lib.makeBinPath [ fontconfig ]);
          cargo_deps = lib.escapeShellArg "${package.cargoDeps}";
          fonts = lib.escapeShellArg "${fonts}";
          model_notice = lib.escapeShellArg "${ocrModels}/LICENSE-CC-BY-SA-4.0.txt";
        }
      }
    '';
    meta =
      removeAttrs old.meta [
        "mainProgram"
        "mainDarwinApp"
      ]
      // {
        description = "Compiled PDF native image clipboard source regression";
        platforms = lib.platforms.linux;
      };
  });
in
runCommand "pdfcraft-wayland-clipboard"
  {
    nativeBuildInputs = [
      python3
      sway
      wl-clipboard
      wayland-utils
      dbus
      fontconfig
    ];
    # Execute on the matching Linux builder, including the desktop's configured ARM builder.
    preferLocalBuild = false;
    passthru = { inherit artifact; };
  }
  ''
    source ${
      replaceVars ./scripts/clipboard-run-check.sh {
        dbus_session_configuration = lib.escapeShellArg "${./scripts/clipboard-session-bus.conf}";
        runner = lib.escapeShellArg "${runner}";
        runner_tests = lib.escapeShellArg "${runnerTests}";
        sway = lib.escapeShellArg (lib.getExe sway);
        wl_copy = lib.escapeShellArg "${wl-clipboard}/bin/wl-copy";
        wl_paste = lib.escapeShellArg "${wl-clipboard}/bin/wl-paste";
        wayland_info = lib.escapeShellArg "${wayland-utils}/bin/wayland-info";
        test_executable = lib.escapeShellArg "${artifact}/libexec/pdfcraft-native-clipboard-tests";
        fixture = lib.escapeShellArg "${fixture}";
      }
    }
  ''
