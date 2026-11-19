{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_24,
}:
let
  source = import ./source.nix;
in
buildNpmPackage (finalAttrs: {
  pname = "homebridge-samsung-tizen";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "tavicu";
    repo = "homebridge-samsung-tizen";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };

  patches = [ ./strict-power-state.patch ];

  nodejs = nodejs_24;
  npmBuildScript = "build";
  postPatch = ''
    cp ${./scripts/strict-power.mts} src/device/strict-power.ts
  '';
  npmInstallFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Homebridge plugin for Samsung Tizen televisions";
    homepage = "https://github.com/tavicu/homebridge-samsung-tizen";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
