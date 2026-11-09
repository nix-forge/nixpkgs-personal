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

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit nodejs_24;
        credential_files_test_mts = "${./credential-files.test.mts}";
        redirect_credentials_test_mts = "${./redirect-credentials.test.mts}";
        nodeModulesCheck = "${./scripts/check_node_modules.mts}";

      }
    }
  '';

  meta = {
    description = "Homebridge plugin for VeSync devices including Levoit Vital purifiers";
    homepage = "https://github.com/mickgiles/homebridge-tsvesync";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
