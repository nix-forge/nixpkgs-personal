{ lib, mplus-outline-fonts }:
mplus-outline-fonts.githubRelease.overrideAttrs (old: {
  strictDeps = true;
  pname = "mplus-outline-fonts-compatible";
  meta = old.meta // {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "M PLUS outline fonts without files duplicated by Google Fonts";
  };
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    cmp "$src/OFL.txt" "$out/share/doc/mplus-outline-fonts-compatible/OFL.txt"
    test "$(find "$out/share/fonts" -type f | wc -l)" -gt 0
    test ! -e "$out/share/fonts/truetype/MPLUS1[wght].ttf"
    runHook postInstallCheck
  '';
  # Google Fonts owns these identical filenames; retain the standalone styles.
  postInstall = (old.postInstall or "") + ''
    install -Dm644 "$src/OFL.txt" "$out/share/doc/mplus-outline-fonts-compatible/OFL.txt"
    rm \
      "$out/share/fonts/truetype/MPLUS1Code[wght].ttf" \
      "$out/share/fonts/truetype/MPLUS1[wght].ttf" \
      "$out/share/fonts/truetype/MPLUS2[wght].ttf" \
      "$out/share/fonts/truetype/MPLUSCodeLatin[wdth,wght].ttf"
  '';
})
