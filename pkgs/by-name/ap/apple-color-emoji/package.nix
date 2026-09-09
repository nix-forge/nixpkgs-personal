{
  lib,
  stdenvNoCC,
  python3,
  fetchurl,
  noto-fonts-color-emoji,
  writeShellApplication,
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
    runHook preInstall
    export XDG_CACHE_HOME="$TMPDIR/font-cache"
    export FONTCONFIG_FILE=${./fonts.conf}
    test "$(fc-scan --format '%{postscriptname}' "$src")" = 'AppleColorEmoji'
    install -Dm644 "$src" "$out/share/fonts/truetype/apple-color-emoji/font.ttf"
    install -Dm444 ${./source.json} "$out/share/doc/apple-color-emoji/manifest.json"
    install -Dm444 ${./README.md} "$out/share/doc/apple-color-emoji/PACKAGING.md"
    ${lib.optionalString repairArtwork ''
      ${checkPython}/bin/python ${./repair.py} \
        "$out/share/fonts/truetype/apple-color-emoji/font.ttf" \
        ${noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf ${emojiData} \
        "$out/share/doc/apple-color-emoji/artwork-repairs.json"
      install -Dm444 ${noto-fonts-color-emoji.src}/fonts/LICENSE \
        "$out/share/doc/apple-color-emoji/Noto-OFL.txt"
      install -Dm444 ${noto-fonts-color-emoji.src}/LICENSE \
        "$out/share/doc/apple-color-emoji/Noto-Apache-2.0.txt"
    ''}
    echo '${if repairArtwork then "repaired" else "unmodified"}' \
      > "$out/share/doc/apple-color-emoji/variant.txt"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${
      if repairArtwork then
        ''
          ${checkPython}/bin/python ${./check.py} \
            "$out/share/fonts/truetype/apple-color-emoji/font.ttf" ${emojiData} --original "$src"
        ''
      else
        ''
          cmp "$src" "$out/share/fonts/truetype/apple-color-emoji/font.ttf"
          test ! -e "$out/share/doc/apple-color-emoji/artwork-repairs.json"
        ''
    }
    runHook postInstallCheck
  '';

  passthru = {
    inherit repairArtwork;
    sourceManifest = source;
    updateScript = lib.getExe (writeShellApplication {
      name = "update-apple-color-emoji";
      runtimeInputs = [
        python3
        fontconfig
      ];
      text = ''
        exec python3 pkgs/by-name/ap/apple-color-emoji/update.py "$@"
      '';
    });
  };
  meta = {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Apple Color Emoji converted to Linux-compatible color bitmap tables";
    homepage = "https://github.com/samuelngs/apple-emoji-ttf";
    license = [ lib.licenses.unfree ] ++ lib.optional repairArtwork lib.licenses.ofl;
    platforms = lib.platforms.linux;
  };
}
