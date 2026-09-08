{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  fontconfig,
  _7zz,
  writeText,
}:
let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  builder = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./unpack.py
      ./font_support.py
    ];
  };
in
stdenvNoCC.mkDerivation {
  pname = source.name;
  inherit (source) version;
  src = fetchurl {
    inherit (source) url hash;
    name = "${source.name}-${source.version}.${source.kind}";
    meta.license = lib.licenses.unfree;
    preferLocalBuild = true;
    derivationArgs.allowSubstitutes = false;
  };

  nativeBuildInputs = [
    python3
    fontconfig
    _7zz
  ];
  strictDeps = true;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  preferLocalBuild = true;
  allowSubstitutes = false;

  installPhase = ''
    runHook preInstall
    export XDG_CACHE_HOME="$TMPDIR/font-cache"
    export FONTCONFIG_FILE=${./fonts.conf}
    python3 ${builder}/unpack.py "$src" ${writeText "font-manifest.json" (builtins.toJSON source)} "$out"
    install -Dm444 ${./README.md} "$out/share/doc/${source.name}/PACKAGING.md"
    runHook postInstall
  '';

  # unpack.py verifies every payload hash and face before and after installation.
  passthru.sourceManifest = source;
  meta = {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Apple developer fonts from ${source.name}";
    homepage = "https://developer.apple.com/fonts/";
    license = lib.licenses.unfree;
    platforms = lib.platforms.unix;
  };
}
