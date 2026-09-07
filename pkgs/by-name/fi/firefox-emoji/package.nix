{
  lib,
  stdenvNoCC,
  fetchurl,
  fontconfig,
  python3,
}:
let
  source = import ./source.nix;
  baseUrl = "https://raw.githubusercontent.com/mozilla/fxemoji/${source.revision}";
  upstreamLicense = fetchurl {
    url = "${baseUrl}/LICENSE.md";
    hash = source.licenseHash;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "firefox-emoji";
  inherit (source) version;

  src = fetchurl {
    url = "${baseUrl}/dist/FirefoxEmoji/FirefoxEmoji.ttf";
    hash = source.fontHash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 "$src" "$out/share/fonts/truetype/FirefoxEmoji.ttf"
    install -Dm444 ${upstreamLicense} "$out/share/doc/${finalAttrs.pname}/LICENSE.md"
    cat > "$out/share/doc/${finalAttrs.pname}/README.txt" <<'EOF'
    Firefox Emoji artwork by Mozilla Foundation. Font distributed unmodified.
    Source: https://github.com/mozilla/fxemoji/tree/${source.revision}
    See LICENSE.md for upstream attribution and license terms.
    This historical font is for explicit family selection, not current Unicode coverage.
    EOF
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    fontconfig
    (python3.withPackages (p: [ p.fonttools ]))
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    export XDG_CACHE_HOME="$TMPDIR/font-cache"
    mkdir -p "$XDG_CACHE_HOME/fontconfig"
    export FONTCONFIG_FILE="$TMPDIR/fonts.conf"
    cat > "$FONTCONFIG_FILE" <<EOF
    <fontconfig><cachedir>$XDG_CACHE_HOME/fontconfig</cachedir></fontconfig>
    EOF
    font="$out/share/fonts/truetype/FirefoxEmoji.ttf"
    cmp "$src" "$font"
    test "$(fc-scan --format '%{family}' "$font")" = 'Firefox Emoji'
    python3 - "$font" <<'PY'
    import sys
    from fontTools.ttLib import TTFont

    with TTFont(sys.argv[1]) as font:
        sample = "😀😁😂😃😄😅😆😇😈😉😊😋😌😍"
        cmap = font.getBestCmap()
        assert all(ord(char) in cmap and font.getGlyphID(cmap[ord(char)]) for char in sample)
        assert font["COLR"].version == 0
        assert font["CPAL"].palettes
        assert all(cmap[ord(char)] in font["COLR"].ColorLayers for char in sample)
    PY
    runHook postInstallCheck
  '';

  # Frozen compatibility release. Automatic updates could change the artwork,
  # family, or license; require an explicit source and license review instead.
  passthru.upstreamRevision = source.revision;

  meta = {
    description = "Historical Firefox OS color emoji font in COLR/CPAL format";
    homepage = "https://github.com/mozilla/fxemoji";
    license = with lib.licenses; [
      asl20
      cc-by-40
    ];
    platforms = lib.platforms.all;
  };
})
