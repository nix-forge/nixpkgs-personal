{
  replaceVars,
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_24,
}:
let
  source = import ./source.nix;
in
buildNpmPackage (finalAttrs: {
  pname = "homebridge-blueair-purifier";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "kovapatrik";
    repo = "homebridge-blueair-purifier";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };

  patches = [ ./redact-api-logs.patch ];

  # Upstream's lock contains lodash 4.17.21. Its fixed release is outside
  # the declared 4.17 range, so both the manifest and lock are pinned here.
  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        package_json = "${./package.json}";
        package_lock_json = "${./package-lock.json}";
      }
    }
  '';

  nodejs = nodejs_24;
  strictDeps = true;
  npmInstallFlags = [ "--ignore-scripts" ];

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit nodejs_24;
        nodeModulesCheck = "${./scripts/check_node_modules.mts}";

      }
    }
  '';

  meta = {
    description = "Homebridge plugin for Blueair cloud purifiers, including Blue Pure 511i Max";
    homepage = "https://github.com/kovapatrik/homebridge-blueair-purifier";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
