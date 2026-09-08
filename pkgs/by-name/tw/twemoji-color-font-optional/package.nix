{ lib, twemoji-color-font }:
twemoji-color-font.overrideAttrs (old: {
  pname = "twemoji-color-font-optional";
  meta = old.meta // {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };
  # Provide the family explicitly without replacing normal text or Noto emoji.
  postInstall = (old.postInstall or "") + ''
    rm -rf "$out/etc/fonts"
  '';
})
