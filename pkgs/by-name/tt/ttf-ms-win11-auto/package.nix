{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  python3,
  fontconfig,
  writeShellApplication,
  nix,
}:

let
  pname = "ttf-ms-win11-auto";
  source = import ./source.nix;

  src = fetchurl {
    inherit (source.src) url hash;
    meta.license = lib.licenses.unfree;
    preferLocalBuild = true;
    derivationArgs.allowSubstitutes = false;
  };
  inspector = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./font_manifest.py
      ./font_support.py
    ];
  };
in
assert (builtins.fromJSON (builtins.readFile ./manifest.json)).version == source.version;
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname src;
  inherit (source) version;

  nativeBuildInputs = [
    _7zz
    python3
    fontconfig
  ];
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    export XDG_CACHE_HOME="$TMPDIR/font-cache"
    export FONTCONFIG_FILE=${./fonts.conf}
    workdir="$TMPDIR/font-extraction"
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

    python3 ${inspector}/font_manifest.py "$extracteddir" ${./manifest.json}

    install -d "$out/share/fonts/truetype"
    for fontPath in "''${fontPaths[@]}"; do
      fontFile="$(basename "$fontPath")"
      install -m444 "$fontPath" "$out/share/fonts/truetype/$fontFile"
    done

    install -d "$out/share/licenses/${finalAttrs.pname}"
    install -m444 "$extracteddir/license.rtf" "$out/share/licenses/${finalAttrs.pname}/license.rtf"

    python3 ${inspector}/font_manifest.py "$out/share/fonts/truetype" ${./manifest.json}
    install -Dm444 ${./manifest.json} "$out/share/doc/${finalAttrs.pname}/manifest.json"
    install -Dm444 ${./README.md} "$out/share/doc/${finalAttrs.pname}/README.md"
    rm -rf "$workdir"

    runHook postInstall
  '';

  preferLocalBuild = true;
  allowSubstitutes = false;
  passthru.updateScript = lib.getExe (writeShellApplication {
    name = "update-windows-fonts";
    runtimeInputs = [
      python3
      fontconfig
      _7zz
      nix
    ];
    text = ''
      exec python3 pkgs/by-name/tt/ttf-ms-win11-auto/update.py "$@"
    '';
  });

  meta = {
    description = "Microsoft Windows 11 TrueType fonts extracted from the Enterprise Evaluation ISO";
    homepage = "https://www.microsoft.com/typography/fonts/product.aspx?PID=164";
    downloadPage = "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise";
    platforms = lib.platforms.unix;
    license = lib.licenses.unfree;
    priority = 5;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };
})
