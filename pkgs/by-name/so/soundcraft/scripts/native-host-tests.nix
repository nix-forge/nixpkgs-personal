{
  lib,
  stdenv,
  replaceVars,
  rust,
  source,
  gitSources,
  package,
  crate,
  testName,
  fonts ? null,
}:
let
  hostName = "${package.pname}-host-tests";
in
package.overrideAttrs (old: {
  pname = hostName;
  buildPhase = ''
    source ${
      replaceVars ./build-native-host-tests.sh {
        inherit crate;
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
        targetName = builtins.replaceStrings [ "-" ] [ "_" ] crate;
        installer = "${./install_native_host_tests.py}";
        testFlags = lib.escapeShellArg "--exact ${testName} --nocapture";
      }
    }
  '';
  postInstall = ''
    source ${
      replaceVars ./install-git-notices.sh {
        pname = hostName;
        gitSources = lib.escapeShellArgs (lib.attrValues gitSources);
        gitMetadata = builtins.toFile "artcraft-git-sources.json" (builtins.toJSON source.gitDependencies);
      }
    }
    source ${
      replaceVars ./post-install.sh (
        {
          pname = hostName;
          inherit (old) cargoDeps;
        }
        // lib.optionalAttrs (fonts != null) { inherit fonts; }
      )
    }
  '';
  postFixup = ''
    rcodesign sign "$out/libexec/${hostName}-libtests"
  '';
  doInstallCheck = false;
  dontStrip = true;
  passthru = { };
  meta = removeAttrs old.meta [ "mainDarwinApp" ] // {
    description = "Native ${package.pname} integration test for macOS services";
    mainProgram = hostName;
    platforms = lib.platforms.darwin;
  };
})
