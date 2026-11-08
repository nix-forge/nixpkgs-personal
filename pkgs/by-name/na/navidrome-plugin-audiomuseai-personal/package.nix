{
  replaceVars,
  fetchFromGitHub,
  jq,
  lib,
  pkgsCross,
  stdenvNoCC,
  runCommand,
  unzip,
}:
let
  source = import ./source.nix;
  upstreamSource = fetchFromGitHub {
    owner = "NeptuneHub";
    repo = "AudioMuse-AI-NV-plugin";
    tag = "v${source.version}";
    inherit (source) hash;
  };
  wasm = pkgsCross.wasi32.navidromePlugins.audiomuseai.overrideAttrs (
    _finalAttrs: previousAttrs: {
      inherit (source) version vendorHash;
      strictDeps = true;
      # The upstream packager reads manifest.json from $src during postInstall,
      # so patch the source itself rather than only the unpacked build tree.
      src = runCommand "audiomuseai-plugin-loopback-source" { nativeBuildInputs = [ jq ]; } ''
        source ${
          replaceVars ./scripts/audiomuseai-plugin-loopback-source.sh {
            inherit upstreamSource;
          }
        }
      '';
      nativeBuildInputs = (previousAttrs.nativeBuildInputs or [ ]) ++ [
        jq
        unzip
      ];
      postInstall = (previousAttrs.postInstall or "") + (builtins.readFile ./scripts/post-install.sh);
      meta = previousAttrs.meta // {
        maintainers = [ ];
        description = "AudioMuse-AI Navidrome plugin with loopback-only HTTP access";
        homepage = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin";
        changelog = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/tag/v${source.version}";
        license = lib.licenses.agpl3Only;
        platforms = lib.platforms.wasi;
        sourceProvenance = [ lib.sourceTypes.fromSource ];
      };
    }
  );
in
stdenvNoCC.mkDerivation {
  # The NixOS Navidrome module finds share/${pname}.ndp. Keep the public
  # package attribute descriptive while matching the actual plugin archive.
  pname = "audiomuseai";
  inherit (source) version;
  strictDeps = true;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit wasm; }}
  '';
  nativeInstallCheckInputs = [
    jq
    unzip
  ];
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;
  # Consumers need the plugin marker and upstream build passthru, while the
  # public archive package runs on the Linux host rather than the WASI target.
  passthru = (removeAttrs (wasm.passthru or { }) [ "updateScript" ]) // {
    # Expose the actual patched source for source audits and lightweight checks.
    wasmSource = wasm.src;
  };
  meta = {
    description = "AudioMuse-AI Navidrome plugin with loopback-only HTTP access";
    homepage = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin";
    changelog = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/tag/v${source.version}";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
