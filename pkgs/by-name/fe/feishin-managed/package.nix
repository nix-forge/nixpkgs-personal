{
  replaceVars,
  lib,
  feishin,
  callPackage,
  asar,
  desktop-file-utils,
  python3,
  nodejs_24,
  stdenv,
}:
let
  scripts = callPackage ./scripts.nix { };
  lifecycleSources = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./mpv_lifecycle.py
      ./mpv-fragments
    ];
  };
in
feishin.overrideAttrs (old: {
  pname = "feishin-managed";
  strictDeps = true;
  meta =
    old.meta
    // {
      maintainers = [ ];
      description = "Music player with managed login and media-player integration";
    }
    // lib.optionalAttrs (
      stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
    ) { mainDarwinApp = "Feishin.app"; };
  nativeInstallCheckInputs =
    (old.nativeInstallCheckInputs or [ ])
    ++ [
      python3
      asar
      nodejs_24
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ desktop-file-utils ];
  doInstallCheck = true;
  postInstallCheck =
    (old.postInstallCheck or "")
    + ''
      source ${
        replaceVars ./scripts/check-installed-helpers.sh {
          darwinHelpers = lib.optionalString stdenv.hostPlatform.isDarwin "mpv-now-playing";
        }
      }
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      python3 ${./scripts/check_app_bundle.py} "$out/Applications/Feishin.app" --expected-version ${lib.escapeShellArg old.version}
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      desktop-file-validate "$out/share/applications/feishin.desktop"
      python3 ${./scripts/check_desktop_entry.py} "$out" "feishin.desktop" "feishin"
    '';
  passthru = (removeAttrs (old.passthru or { }) [ "updateScript" ]) // {
    tests = (old.passthru.tests or { }) // {
      managed-login = scripts;
    };
  };
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    asar
    python3
    nodejs_24
  ];
  postInstall = (old.postInstall or "") + ''
    source ${
      replaceVars ./scripts/post-install.sh {
        inherit scripts lifecycleSources;
        python = "${python3}/bin/python";
        lifecycleTest = "${./mpv-lifecycle.test.mts}";
        darwinIntegration = lib.optionalString stdenv.hostPlatform.isDarwin ''
          source ${
            replaceVars ./scripts/darwin-post-install.sh {
              python = "${python3}/bin/python";
              nativeTitlebar = "${./native_titlebar.py}";
              inherit scripts;
            }
          }
        '';
      }
    }
  '';
})
