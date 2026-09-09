{
  lib,
  stdenvNoCC,
  fetchurl,
  fontconfig,
  python3,
  writers,
}:
let
  source = import ./source.nix;
  apacheLicense = fetchurl {
    url = "https://www.apache.org/licenses/LICENSE-2.0.txt";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };
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
    install -Dm444 ${apacheLicense} "$out/share/doc/${finalAttrs.pname}/Apache-2.0.txt"
    cat > "$out/share/doc/${finalAttrs.pname}/README.txt" <<'EOF'
    Firefox Emoji artwork by Mozilla Foundation. Font distributed unmodified.
    Source: https://github.com/mozilla/fxemoji/tree/${source.revision}
    See LICENSE.md for upstream attribution and license terms.
    This historical font is for explicit family selection, not current Unicode coverage.
    EOF
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ fontconfig ];
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
    ${
      lib.getExe (
        writers.writePython3Bin "check-installed-assets" {
          libraries = [ python3.pkgs.fonttools ];
          flakeIgnore = [ "E501" ];
        } ./check-installed.py
      )
    } "$font"
    runHook postInstallCheck
  '';

  # Frozen compatibility release. Automatic updates could change the artwork,
  # family, or license; require an explicit source and license review instead.
  passthru.upstreamRevision = source.revision;

  meta = {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Historical Firefox OS color emoji font in COLR/CPAL format";
    homepage = "https://github.com/mozilla/fxemoji";
    license = with lib.licenses; [
      asl20
      cc-by-40
    ];
    platforms = lib.platforms.all;
  };
})
