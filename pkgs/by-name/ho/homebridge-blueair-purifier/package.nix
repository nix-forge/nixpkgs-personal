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
buildNpmPackage (_finalAttrs: {
  pname = "homebridge-blueair-purifier";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "kovapatrik";
    repo = "homebridge-blueair-purifier";
    inherit (source) rev;
    inherit (source) hash;
  };

  # The selected upstream commit includes log redaction and the Lodash minimum.
  # Retain the reviewed transitive security updates until its lock catches up.
  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        package_lock_json = "${./package-lock.json}";
      }
    }
  '';

  nodejs = nodejs_24;
  strictDeps = true;
  npmInstallFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Homebridge plugin for Blueair cloud purifiers, including Blue Pure 511i Max";
    homepage = "https://github.com/kovapatrik/homebridge-blueair-purifier";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
