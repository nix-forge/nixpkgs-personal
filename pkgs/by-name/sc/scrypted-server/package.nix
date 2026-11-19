{
  replaceVars,
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_24,
  python3,
  pkg-config,
  esbuild,
  vips,
  librsvg,
}:
let
  source = import ./source.nix;
  # The native Sharp build uses this library, rather than bundled @img binaries.
  # The backport applies without fuzz to the reviewed 2.62.3 and 2.63.0 sources.
  svgFixed =
    (lib.versionAtLeast librsvg.version "2.62.4" && lib.versionOlder librsvg.version "2.62.90")
    || lib.versionAtLeast librsvg.version "2.63.2";
  svgLibrary =
    if
      !(
        builtins.elem librsvg.version [
          "2.62.3"
          "2.63.0"
        ]
        || svgFixed
      )
    then
      throw "Review Scrypted's librsvg entity backport against the selected version"
    else if svgFixed then
      librsvg
    else
      librsvg.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./librsvg-duplicate-entities.patch ];
      });
  nativeVips = vips.override { librsvg = svgLibrary; };
in
buildNpmPackage (finalAttrs: {
  pname = "scrypted-server";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "koush";
    repo = "scrypted";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };
  sourceRoot = "source/server";

  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        inherit nodejs_24;
        package_lock_json = "${./package-lock.json}";
        manifestProgram = "${./scripts/patch-manifest.mts}";
        dependencyPolicy = "${./dependency-policy.json}";

      }
    }
  '';

  nodejs = nodejs_24;
  strictDeps = true;
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    python3
    pkg-config
    esbuild
  ];
  buildInputs = [ nativeVips ];
  env = {
    npm_config_build_from_source = "true";
    SHARP_FORCE_GLOBAL_LIBVIPS = "1";
  };
  buildPhase = ''
    source ${
      replaceVars ./scripts/build-phase.sh {
        tarPatch = "${./pax-entry-metadata.patch}";
      }
    }
  '';

  # The upstream postinstall downloads a Python interpreter and ffmpeg-static
  # downloads a binary. Both are supplied by Nix at runtime instead.
  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        launcherSource = replaceVars ./scripts/scrypted-serve.sh.in {
          inherit nodejs_24;
          runtimeOutput = null;
        };
        inherit nodejs_24;
      }
    }
  '';

  meta = {
    description = "Scrypted home video integration server";
    homepage = "https://github.com/koush/scrypted";
    license = with lib.licenses; [
      isc
      blueOak100
    ];
    platforms = lib.platforms.linux;
    mainProgram = "scrypted-serve";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
