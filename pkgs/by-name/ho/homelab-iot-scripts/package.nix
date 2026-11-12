{
  replaceVars,
  buildNpmPackage,
  nodejs_24,
  lib,
}:
buildNpmPackage {
  pname = "homelab-iot-scripts";
  version = "1";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./.oxlintrc.json
      ./package.json
      ./package-lock.json
      ./tsconfig.json
      ./homebridge-initialize.cts
      ./check-homebridge-ui-auth.mts
      ./scrypted-api.cts
      ./scrypted-auth.cts
      ./scrypted-auth.test.cts
      ./scrypted-managed-settings.cts
      ./scrypted-managed-settings.test.cts
      ./scrypted-plugin-install.cts
      ./scrypted-plugin-install.test.cts
      ./scrypted-plugin-marker.cts
      ./scrypted-plugin-marker.test.cts
    ];
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-h45sXW6SMB2Es4nQXvg0n4gGddnJwFg4MCUKS4ylE+g=";
  strictDeps = true;
  dontNpmBuild = true;
  buildPhase = builtins.readFile ./scripts/build-phase.sh;
  doCheck = true;
  checkPhase = builtins.readFile ./scripts/check-phase.sh;
  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        licenseFile = "${./LICENSE}";
      }
    }
  '';
  meta = {
    description = "Initialization and authentication helpers for Homebridge and Scrypted";
    homepage = "https://github.com/nix-forge/nixpkgs-personal/tree/main/pkgs/by-name/ho/homelab-iot-scripts";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
