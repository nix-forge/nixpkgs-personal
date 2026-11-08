{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  python3,
  fontconfig,
}:

let
  pname = "ttf-ms-win11-auto";
  source = import ./source.nix;

  src = fetchurl {
    inherit (source.src) url hash;
    meta.license = lib.licenses.unfree;
    preferLocalBuild = true;
    derivationArgs = {
      allowSubstitutes = false;
      # Keep the upstream filename while matching the package's unfree predicate.
      inherit pname;
    };
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
    source ${
      replaceVars ./scripts/install-phase.sh {
        fonts_conf = "${./fonts.conf}";
        inherit inspector;
        manifest_json = "${./manifest.json}";
        inherit (finalAttrs) pname;
        readme = "${./README.md}";
      }
    }
  '';

  preferLocalBuild = true;
  allowSubstitutes = false;
  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    description = "Microsoft Windows 11 TrueType fonts extracted from the Enterprise Evaluation ISO";
    homepage = "https://www.microsoft.com/typography/fonts/product.aspx?PID=164";
    downloadPage = "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise";
    platforms = lib.platforms.unix;
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };
})
