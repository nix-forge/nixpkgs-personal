{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  fontconfig,
  python3,
  writers,
}:
let
  source = import ./source.nix;
  apacheLicense = fetchurl {
    url = "https://www.apache.org/licenses/LICENSE-2.0.txt";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };
  baseUrl = "https://raw.githubusercontent.com/mozilla/fxemoji/${source.revision}";
  upstreamLicense = fetchurl {
    url = "${baseUrl}/LICENSE.md";
    hash = source.licenseHash;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "firefox-emoji";
  inherit (source) version;

  src = fetchurl {
    url = "${baseUrl}/dist/FirefoxEmoji/FirefoxEmoji.ttf";
    hash = source.fontHash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit upstreamLicense;
        inherit (finalAttrs) pname;
        inherit apacheLicense;
        source_revision = source.revision;
      }
    }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ fontconfig ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        assetsCheck = lib.getExe (
          writers.writePython3Bin "check-installed-assets" {
            libraries = [ python3.pkgs.fonttools ];
            flakeIgnore = [ "E501" ];
          } ./check_installed.py
        );
      }
    }
  '';

  # Frozen compatibility release. Automatic updates could change the artwork,
  # family, or license; require an explicit source and license review instead.
  passthru.upstreamRevision = source.revision;

  meta = {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Historical Firefox OS color emoji font in COLR/CPAL format";
    homepage = "https://github.com/mozilla/fxemoji";
    license = with lib.licenses; [
      asl20
      cc-by-40
    ];
    platforms = lib.platforms.all;
  };
})
