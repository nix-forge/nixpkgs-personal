{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  python3,
  fetchurl,
  noto-fonts-color-emoji,
  fontconfig,
  repairArtwork ? true,
}:
let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  checkPython = python3.withPackages (p: [
    p.fonttools
    p.uharfbuzz
    p.pillow
  ]);
  emojiData = fetchurl {
    url = "https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt";
    hash = "sha256-HYqUT4jXlS9+98UWf+88Z5lbyuJFQ5SXECMbA6IBrNo=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "apple-color-emoji";
  inherit (source) version;
  src = fetchurl {
    inherit (source) url hash;
    name = "${source.name}-${source.version}.${source.kind}";
    meta.license = lib.licenses.unfree;
    preferLocalBuild = true;
    derivationArgs.allowSubstitutes = false;
  };

  strictDeps = true;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  nativeBuildInputs = [ fontconfig ];
  preferLocalBuild = true;
  allowSubstitutes = false;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        fonts_conf = "${./fonts.conf}";
        source_json = "${./source.json}";
        readme = "${./README.md}";
        repairArtworkCommand = lib.optionalString repairArtwork ''
          ${checkPython}/bin/python ${./repair_missing_artwork.py} \
            "$out/share/fonts/truetype/apple-color-emoji/font.ttf" \
            ${noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf ${emojiData} \
            "$out/share/doc/apple-color-emoji/artwork-repairs.json"
          install -Dm444 ${noto-fonts-color-emoji.src}/fonts/LICENSE \
            "$out/share/doc/apple-color-emoji/Noto-OFL.txt"
          install -Dm444 ${noto-fonts-color-emoji.src}/LICENSE \
            "$out/share/doc/apple-color-emoji/Noto-Apache-2.0.txt"
        '';
        artworkVariant = if repairArtwork then "repaired" else "unmodified";
      }
    }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        checkArtworkCommand =
          if repairArtwork then
            ''
              ${checkPython}/bin/python ${./check_emoji_artwork.py} \
                "$out/share/fonts/truetype/apple-color-emoji/font.ttf" ${emojiData} --original "$src"
            ''
          else
            ''
              cmp "$src" "$out/share/fonts/truetype/apple-color-emoji/font.ttf"
              test ! -e "$out/share/doc/apple-color-emoji/artwork-repairs.json"
            '';
      }
    }
  '';

  passthru = {
    inherit repairArtwork;
    sourceManifest = source;
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
  };
  meta = {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Apple Color Emoji converted to Linux-compatible color bitmap tables";
    homepage = "https://github.com/samuelngs/apple-emoji-ttf";
    license = [ lib.licenses.unfree ] ++ lib.optional repairArtwork lib.licenses.ofl;
    platforms = lib.platforms.linux;
  };
}
