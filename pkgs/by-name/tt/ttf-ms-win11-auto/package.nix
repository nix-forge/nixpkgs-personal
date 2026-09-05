{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:

let
  pname = "ttf-ms-win11-auto";
  source = import ./source.nix;

  src = fetchurl { inherit (source.src) url hash; };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname src;
  inherit (source) version;

  nativeBuildInputs = [ _7zz ];
  dontUnpack = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    workdir="$out/.extract-work"
    isodir="$workdir/iso"
    extracteddir="$workdir/extracted"
    mkdir -p "$isodir" "$extracteddir"

    7zz x -y -o"$isodir" "$src" 'sources/install.wim' >/dev/null

    7zz e -y -o"$extracteddir" "$isodir/sources/install.wim" \
      'Windows/Fonts/*' \
      'Windows/System32/Licenses/neutral/*/*/license.rtf' >/dev/null

    if [ ! -f "$extracteddir/license.rtf" ]; then
      echo "Missing license.rtf in install.wim extraction output" >&2
      exit 1
    fi

    mapfile -t fontPaths < <(
      find "$extracteddir" -maxdepth 1 -type f \
        \( -iname '*.ttf' -o -iname '*.ttc' \) \
        -print | LC_ALL=C sort -f
    )
    if [ "''${#fontPaths[@]}" -eq 0 ]; then
      echo "No .ttf/.ttc font files were extracted from install.wim" >&2
      exit 1
    fi

    install -d "$out/share/fonts/truetype"
    for fontPath in "''${fontPaths[@]}"; do
      fontFile="$(basename "$fontPath")"
      install -m444 "$fontPath" "$out/share/fonts/truetype/$fontFile"
    done

    install -d "$out/share/licenses/${finalAttrs.pname}"
    install -m444 "$extracteddir/license.rtf" "$out/share/licenses/${finalAttrs.pname}/license.rtf"

    rm -rf "$workdir"

    runHook postInstall
  '';

  preferLocalBuild = true;
  allowSubstitutes = false;
  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Microsoft Windows 11 TrueType fonts extracted from the Enterprise Evaluation ISO";
    homepage = "https://www.microsoft.com/typography/fonts/product.aspx?PID=164";
    downloadPage = "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise";
    platforms = lib.platforms.all;
    license = lib.licenses.unfree;
    priority = 5;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
