{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  fontconfig,
}:
let
  source = import ./source.nix;
  python = python3.withPackages (ps: [
    ps.nanoemoji
    ps.uharfbuzz
  ]);
  checkFont = artwork: ''
    source ${
      replaceVars ./scripts/check-emoji-font.sh {
        fonts_conf = "${./fonts.conf}";
        check_py = "${./check_emoji_shaping.py}";
        inherit artwork;
      }
    }
  '';
  # Keep vector compilation separate from the inexpensive encoding pass.
  compiledFont = stdenvNoCC.mkDerivation (_finalAttrs: {
    pname = "mutant-standard-emoji";
    inherit (source) version;

    src = fetchurl {
      url = "https://mutant.tech/dl/${source.version}/mtnt_${source.version}_code_svg.zip";
      hash = source.artworkHash;
    };

    strictDeps = true;
    nativeBuildInputs = [ python ];
    unpackPhase = builtins.readFile ./scripts/unpack-phase.sh;
    dontConfigure = true;

    buildPhase = ''
      source ${
        replaceVars ./scripts/build-colr-font.sh {
          prepare_py = "${./normalize_svg_units.py}";
          finish_py = "${./stamp_font_metadata.py}";
          source_version = source.version;
        }
      }
    '';

    installPhase = ''
      source ${
        replaceVars ./scripts/install-colr-font.sh {
          readme = "${./README.md}";
        }
      }
    '';

    doInstallCheck = true;
    nativeInstallCheckInputs = [ fontconfig ];
    installCheckPhase = checkFont "emoji";

    meta = {
      sourceProvenance = [ lib.sourceTypes.fromSource ];
      description = "Mutant Standard emoji artwork compiled as a scalable COLRv1 font";
      homepage = "https://mutant.tech";
      license = lib.licenses.cc-by-nc-sa-40;
      platforms = lib.platforms.unix;
    };
  });
in
stdenvNoCC.mkDerivation {
  inherit (compiledFont) pname version meta;
  strictDeps = true;
  nativeBuildInputs = [ python ];
  dontUnpack = true;
  dontConfigure = true;

  buildPhase = ''
    source ${
      replaceVars ./scripts/build-phase.sh {
        compiledFont_src = compiledFont.src;
        inherit compiledFont;
        normalize_shaping_py = "${./normalize_shaping.py}";
      }
    }
  '';

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit compiledFont;
        encoding_md = "${./encoding.md}";
      }
    }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ fontconfig ];
  installCheckPhase = checkFont "artwork/emoji";

  passthru = { inherit compiledFont; };
}
