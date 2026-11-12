{
  replaceVars,
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_24,
  perl,
}:
let
  source = import ./source.nix;
in
buildNpmPackage (finalAttrs: {
  pname = "homebridge-lg-thinq-mp";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "mp-consulting";
    repo = "homebridge-lg-thinq";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };

  nodejs = nodejs_24;
  strictDeps = true;
  nativeBuildInputs = [ perl ];
  # Homebridge UI is a development dependency; its native terminal addon is
  # not part of this plugin. The build script compiles the plugin and copies UI assets.
  npmFlags = [ "--ignore-scripts" ];

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit nodejs_24;
        nodeModulesCheck = "${./scripts/check_node_modules.mts}";

      }
    }
  '';

  passthru.homebridgePluginName = "@mp-consulting/homebridge-lg-thinq";

  meta = {
    description = "Homebridge plugin for LG ThinQ appliances";
    homepage = "https://github.com/mp-consulting/homebridge-lg-thinq";
    license = with lib.licenses; [
      asl20
      mit
    ];
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
