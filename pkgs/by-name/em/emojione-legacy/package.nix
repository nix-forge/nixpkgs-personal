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
  adobeLicense = fetchurl {
    url = "https://raw.githubusercontent.com/adobe-fonts/emojione-color/835b4ef8384f55ecf9abf7ecc943a3980884690b/LICENSE.md";
    hash = "sha256-p54R2CS+ck02LIwUO0EwiJxmzy70fxblrYO9eW3RgYM=";
  };
  baseUrl = "https://raw.githubusercontent.com/joypixels/emojione/${source.revision}";
  upstreamLicense = fetchurl {
    url = "${baseUrl}/LICENSE.md";
    hash = source.licenseHash;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "emojione-legacy";
  inherit (source) version;

  src = fetchurl {
    url = "${baseUrl}/assets/fonts/emojione-svg.otf";
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
        inherit adobeLicense;
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
    description = "Legacy EmojiOne 2 color emoji font in SVG OpenType format";
    homepage = "https://github.com/joypixels/emojione";
    license = with lib.licenses; [
      mit
      cc-by-40
    ];
    platforms = lib.platforms.all;
  };
})
