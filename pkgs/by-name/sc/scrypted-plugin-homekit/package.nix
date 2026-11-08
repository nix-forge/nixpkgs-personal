{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  gnutar,
  python3,
}:
let
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "scrypted-plugin-homekit";
  inherit (source) version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@scrypted/homekit/-/homekit-${finalAttrs.version}.tgz";
    inherit (source) hash;
  };

  strictDeps = true;
  dontUnpack = true;
  nativeBuildInputs = [
    gnutar
    python3
  ];

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit python3;
        check_py = "${./check_plugin_archive.py}";
        inherit (finalAttrs) version;
      }
    }
  '';

  meta = {
    description = "Published HomeKit integration plugin artifact for Scrypted";
    homepage = "https://github.com/koush/scrypted/tree/main/plugins/homekit";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    # The published bundle differs from its Git manifest version and uses a
    # local HAP-NodeJS dependency absent from the exact published source commit.
    sourceProvenance = [ lib.sourceTypes.obfuscatedCode ];
  };
})
