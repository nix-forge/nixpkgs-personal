{ mplus-outline-fonts }:
mplus-outline-fonts.githubRelease.overrideAttrs (old: {
  pname = "mplus-outline-fonts-compatible";
  # Google Fonts owns these identical filenames; retain the standalone styles.
  postInstall = (old.postInstall or "") + ''
    rm \
      "$out/share/fonts/truetype/MPLUS1Code[wght].ttf" \
      "$out/share/fonts/truetype/MPLUS1[wght].ttf" \
      "$out/share/fonts/truetype/MPLUS2[wght].ttf" \
      "$out/share/fonts/truetype/MPLUSCodeLatin[wdth,wght].ttf"
  '';
})
