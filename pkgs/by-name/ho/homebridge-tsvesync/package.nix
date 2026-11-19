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
  pname = "homebridge-tsvesync";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "mickgiles";
    repo = "homebridge-tsvesync";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };
  patches = [ ./credential-files.patch ];

  # Upstream does not publish a lockfile. Keep the reviewed npm resolution
  # beside this recipe so Nix fetches every dependency by its recorded hash.
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
    description = "Homebridge plugin for VeSync devices including Levoit Vital purifiers";
    homepage = "https://github.com/mickgiles/homebridge-tsvesync";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
