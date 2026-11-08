{
  lib,
  stdenv,
  replaceVars,
  rust,
  source,
  gitSources,
  fonts,
  japaneseFontLicense,
  package,
}:
let
  hostName = "${package.pname}-host-tests";
in
package.overrideAttrs (old: {
  pname = hostName;
  buildPhase = ''
    source ${
      replaceVars ./build-native-host-tests.sh {
        crate = "artcraft-launcher-native";
        rustTarget = stdenv.hostPlatform.rust.rustcTargetSpec;
        cargoEnvironment = rust.envVars.setEnv;
      }
    }
  '';
  postBuild = "";
  doCheck = false;
  postCheck = "";
  installPhase = ''
    source ${
      replaceVars ./install-native-host-tests.sh {
        inherit hostName;
        targetName = "artcraft_launcher_native";
        installer = "${./install_native_host_tests.py}";
      }
    }
  '';
  postInstall = ''
    source ${
      replaceVars ./install-native-host-notices.sh {
        inherit hostName fonts japaneseFontLicense;
        inherit (old) cargoDeps;
        gitNotices = replaceVars ./install-git-notices.sh {
          pname = hostName;
          gitSources = lib.escapeShellArgs (lib.attrValues gitSources);
          gitMetadata = builtins.toFile "artcraft-git-sources.json" (builtins.toJSON source.gitDependencies);
        };
      }
    }
  '';
  postFixup = ''
    rcodesign sign "$out/libexec/${hostName}-libtests"
  '';
  doInstallCheck = false;
  dontStrip = true;
  passthru = { };
  meta = removeAttrs old.meta [ "mainDarwinApp" ] // {
    description = "Native Craft Launcher integration tests for macOS services";
    mainProgram = hostName;
    platforms = lib.platforms.darwin;
  };
})
