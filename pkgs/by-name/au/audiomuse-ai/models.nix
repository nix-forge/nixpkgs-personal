{
  lib,
  stdenvNoCC,
  fetchurl,
  gnutar,
  gzip,
}:
let
  source = import ./source.nix;
  fromAudioMuse =
    name: hash:
    fetchurl {
      url = "https://github.com/NeptuneHub/AudioMuse-AI/releases/download/${source.modelRelease}/${name}";
      inherit hash;
    };
  fromDclap =
    name: hash:
    fetchurl {
      url = "https://github.com/NeptuneHub/AudioMuse-AI-DCLAP/releases/download/${source.dclapRelease}/${name}";
      inherit hash;
    };
  fromSae =
    name: hash:
    fetchurl {
      url = "https://github.com/NeptuneHub/AudioMuse-AI-SAE/releases/download/${source.saeRelease}/${name}";
      inherit hash;
    };
  files = {
    "clap_text_model.onnx" =
      fromAudioMuse "clap_text_model.onnx" "sha256-IA1I85Bf8fJyr1AG3ZhR+UBxp93k6v2cB7wJxaxlpxQ=";
    "musicnn_embedding.onnx" =
      fromAudioMuse "musicnn_embedding.onnx" "sha256-pIrYh5UKVXrvu03N31itSAIhP/X8b7Ue2jUHzXl7ubA=";
    "musicnn_prediction.onnx" =
      fromAudioMuse "musicnn_prediction.onnx" "sha256-DU543UPGEK7IjAmeQfSolpeX2lrCYS6myiH6qeGkKPM=";
    "neural_fingerprint.onnx" =
      fromAudioMuse "neural_fingerprint.onnx" "sha256-tlgU2qfafXw96JQlCTbbbkNj94vUHjEPRZfdybRvKVs=";
    "neural_fingerprint_pq.npz" =
      fromAudioMuse "neural_fingerprint_pq.npz" "sha256-iLGmb945pBaHTFGB6OSEI19iGl3GNw8FWVkQ4KMz7Do=";
    "model_epoch_36.onnx" =
      fromDclap "model_epoch_36.onnx" "sha256-F4YEA/j8kK/4rAYyoHQeteWNjAsK0vzlztlnJ0sOqXE=";
    "model_epoch_36.onnx.data" =
      fromDclap "model_epoch_36.onnx.data" "sha256-KnNbI8Kq17Etn/yFM0zrzGWcB2ltL/YOLjeNoott9lc=";
    "dclap_sae_k20_d1024_best_encoder.onnx" =
      fromSae "dclap_sae_k20_d1024_best_encoder.onnx" "sha256-2BcjzH0UVmBX6LGZ8rxOo+oeLKenlSmkDz/NU5n5dvY=";
    "dclap_sae_k20_d1024_best_decoder.onnx" =
      fromSae "dclap_sae_k20_d1024_best_decoder.onnx" "sha256-exbuBseYEGZK6gJuK20ptl22jXVth77oioVaHiz/y/Y=";
  };
  archives = {
    huggingface = fromAudioMuse "huggingface_models.tar.gz" "sha256-AqeNbkI0BMcnEWj3QPF+Q9vBCUf3Rt/EIFZwinRsyz0=";
    gte = fromAudioMuse "lyrics_model_gte_vnni.tar.gz" "sha256-X4pJyHPHYvAajaeQ9B+Z29qsbx8g1MCi26QHzMYMx8w=";
    silero = fromAudioMuse "lyrics_model_silero_vad.tar.gz" "sha256-ZeXlw9e/XlvHxHv0K7vmadv6FZVDvUdeDCPO06p6w7Q=";
    whisper = fromAudioMuse "lyrics_model_whisper.tar.gz" "sha256-+p9IJeGpGDlMGmOwy3ykOrHfi+kDVa0D56+V7j0/FRE=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "audiomuse-ai-models";
  inherit (source) version;

  dontUnpack = true;
  strictDeps = true;
  nativeBuildInputs = [
    gnutar
    gzip
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/model/huggingface"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: file: "cp ${file} \"$out/model/${name}\"") files
    )}
    tar -xzf ${archives.huggingface} -C "$out/model/huggingface"
    tar -xzf ${archives.gte} -C "$out/model"
    tar -xzf ${archives.silero} -C "$out/model"
    tar -xzf ${archives.whisper} -C "$out/model"

    # AudioMuse only loads the RoBERTa tokenizer from this cache. Removing the
    # unused BERT/BART weights saves about 1.4 GB without changing inference.
    find "$out/model/huggingface" -type l -print0 | while IFS= read -r -d $'\0' link; do
      target="$(readlink -f "$link")"
      cp --remove-destination "$target" "$link"
    done
    rm -rf \
      "$out/model/huggingface/hub/models--bert-base-uncased" \
      "$out/model/huggingface/hub/models--facebook--bart-base"
    find "$out/model/huggingface/hub/models--roberta-base" -type f \
      \( -name model.safetensors -o -name pytorch_model.bin \) -delete
    find "$out/model/huggingface/hub/models--roberta-base" -type f \
      -size +10M -delete

    test -s "$out/model/musicnn_embedding.onnx"
    test -s "$out/model/model_epoch_36.onnx.data"
    test -s "$out/model/whisper-small-onnx/encoder_model.onnx"
    test -s "$out/model/gte-multilingual-base/tokenizer.json"
    test -z "$(find -L "$out/model" -type l -print -quit)"
    runHook postInstall
  '';

  meta = {
    description = "Pinned inference models for AudioMuse-AI";
    homepage = "https://github.com/NeptuneHub/AudioMuse-AI";
    license = lib.licenses.agpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };
}
