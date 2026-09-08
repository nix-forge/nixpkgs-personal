{ lib, twemoji-color-font }:
twemoji-color-font.overrideAttrs (old: {
  strictDeps = true;
  pname = "twemoji-color-font-optional";
  meta = old.meta // {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Twitter color emoji font without default Fontconfig substitutions";
    platforms = lib.platforms.unix;
  };
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$(find "$out/share/fonts" -type f | wc -l)" -gt 0
    test ! -e "$out/etc/fonts"
    runHook postInstallCheck
  '';
  # Provide the family explicitly without replacing normal text or Noto emoji.
  postInstall = (old.postInstall or "") + ''
    rm -rf "$out/etc/fonts"
  '';
})
