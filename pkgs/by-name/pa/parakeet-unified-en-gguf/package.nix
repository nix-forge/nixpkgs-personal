{
  lib,
  stdenvNoCC,
  fetchurl,
  callPackage,
}:
let
  source = import ./source.nix;
  licenseAgreement = fetchurl {
    url = "https://www.nvidia.com/content/dam/en-zz/Solutions/license-agreements/enterprise-software/nvidia-open-model-license-agreements-24-10-2025.pdf";
    hash = "sha256-TS+1kKqbMMR/IFi/8XKR33+iqgwb13WiBwPam7Jnz6s=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "parakeet-unified-en-gguf";
  inherit (source) version;
  src = fetchurl {
    url = "https://huggingface.co/${source.repo}/resolve/${source.rev}/${source.filename}";
    inherit (source) hash;
  };
  strictDeps = true;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    install -Dm444 "$src" "$out/share/${finalAttrs.pname}/${source.filename}"
    install -Dm444 ${licenseAgreement} "$out/share/doc/${finalAttrs.pname}/LICENSE-NVIDIA.pdf"
    cat > "$out/share/doc/${finalAttrs.pname}/Notice" <<'NOTICE'
    Licensed by NVIDIA Corporation under the NVIDIA Open Model License
    Original model: https://huggingface.co/nvidia/parakeet-unified-en-0.6b
    GGUF conversion by Handy Computer: https://huggingface.co/${source.repo}
    Conversion revision: ${source.rev}
    The GGUF repository additionally labels the conversion CC-BY-4.0:
    https://creativecommons.org/licenses/by/4.0/
    Model weights are packaged unchanged. NVIDIA's underlying terms still apply.
    NOTICE
    runHook postInstall
  '';
  passthru = {
    # A distinct local name prevents Handy's catalog/HF cache from shadowing
    # the Nix-selected weights. The stem is Handy's discovered Local model ID.
    modelId = "nix-${lib.removeSuffix ".gguf" source.filename}";
    modelFilename = "nix-${source.filename}";
    modelFile = "${finalAttrs.finalPackage}/share/${finalAttrs.pname}/${source.filename}";
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
  };
  meta = {
    description = "Parakeet Unified EN 0.6B Q8 GGUF English speech recognition weights";
    homepage = "https://huggingface.co/${source.repo}";
    # The converted repository's CC-BY label does not replace the original
    # checkpoint's use restrictions. Preserve both attributions and the agreement.
    license = [
      {
        shortName = "NVIDIA-Open-Model";
        fullName = "NVIDIA Open Model License";
        url = "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/";
        free = false;
        redistributable = true;
      }
      lib.licenses.cc-by-40
    ];
    platforms = lib.platforms.all;
    # Nixpkgs has no predefined provenance type for trained model data.
    sourceProvenance = [
      {
        shortName = "binaryModelWeights";
        isSource = false;
      }
    ];
  };
})
