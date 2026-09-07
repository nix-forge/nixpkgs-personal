{ twemoji-color-font }:
twemoji-color-font.overrideAttrs (old: {
  pname = "twemoji-color-font-optional";
  # Provide the family explicitly without replacing normal text or Noto emoji.
  postInstall = (old.postInstall or "") + ''
    rm -rf "$out/etc/fonts"
  '';
})
