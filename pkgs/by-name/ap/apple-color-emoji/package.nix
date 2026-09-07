{
  lib,
  apple-fonts,
  python3,
  fetchurl,
  noto-fonts-color-emoji,
  writeShellApplication,
  fontconfig,
}:
let
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
(apple-fonts.fromSource { manifestFile = ./source.json; }).overrideAttrs (old: {
  passthru = old.passthru // {
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
  postInstall = ''
    install -Dm444 ${./README.md} "$out/share/doc/apple-color-emoji/PACKAGING.md"
    chmod u+w "$out/share/fonts/truetype/apple-color-emoji/font.ttf"
    ${checkPython}/bin/python ${./repair.py} \
      "$out/share/fonts/truetype/apple-color-emoji/font.ttf" \
      ${noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf ${emojiData} \
      "$out/share/doc/apple-color-emoji/artwork-repairs.json"
    install -Dm444 ${noto-fonts-color-emoji.src}/fonts/LICENSE \
      "$out/share/doc/apple-color-emoji/Noto-OFL.txt"
    install -Dm444 ${noto-fonts-color-emoji.src}/LICENSE \
      "$out/share/doc/apple-color-emoji/Noto-Apache-2.0.txt"
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${checkPython}/bin/python ${./check.py} \
      "$out/share/fonts/truetype/apple-color-emoji/font.ttf" ${emojiData} --original "$src"
    runHook postInstallCheck
  '';
  meta = old.meta // {
    description = "Apple Color Emoji converted to Linux-compatible color bitmap tables";
    homepage = "https://github.com/samuelngs/apple-emoji-ttf";
    platforms = lib.platforms.linux;
  };
})
