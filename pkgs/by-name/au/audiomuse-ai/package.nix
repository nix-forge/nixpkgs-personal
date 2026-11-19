{
  replaceVars,
  lib,
  callPackage,
  fetchFromGitHub,
  makeWrapper,
  python313,
  python313Packages,
  chromaprint,
}:
let
  source = import ./source.nix;
  appSource = source.app;
  audiomuse-ai-models = callPackage ./models.nix { };
  googleGenai = callPackage ./google-genai.nix { inherit source; };
  huggingfaceHub = callPackage ./huggingface-hub.nix { inherit source; };
  mistralai = callPackage ./mistralai.nix { inherit source; };
  inherit (python313Packages) safetensors;
  tokenizers =
    (python313Packages.tokenizers.override { huggingface-hub = huggingfaceHub; }).overridePythonAttrs
      (old: {
        # This network-only training module is already excluded by upstream's
        # class filter. Exclude the file before collection so its datasets import
        # cannot introduce a second, incompatible Hub into the check environment.
        # Keep the remaining upstream offline suite and its pinned local data.
        nativeCheckInputs = builtins.filter (
          input: (input.pname or null) != "datasets"
        ) old.nativeCheckInputs;
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
          "tests/documentation/test_tutorial_train_from_iterators.py"
        ];
      });
  transformers = callPackage ./transformers.nix {
    inherit
      source
      huggingfaceHub
      safetensors
      tokenizers
      ;
  };
  # The supported Nixpkgs source excludes inline-snapshot's formatter-sensitive
  # documentation tests. Reuse its ordinary Narwhals/scikit-learn closure and
  # upstream checks instead of disabling the entire dataframe suite.
  appSourcePath = fetchFromGitHub {
    owner = "NeptuneHub";
    repo = "AudioMuse-AI";
    inherit (appSource) rev hash;
  };
  python = python313.withPackages (p: [
    p.argon2-cffi
    p.av
    p.cryptography
    p.flasgger
    p.flask
    p.flask-cors
    p.flatbuffers
    p.ftfy
    googleGenai
    p.gunicorn
    p.httpx
    huggingfaceHub
    p.langdetect
    p.librosa
    mistralai
    p.mutagen
    p.numba
    p.numkong
    p.numpy
    p.onnx
    p.onnxruntime
    p.packaging
    p.protobuf
    p.psutil
    p.psycopg2
    p.pyjwt
    p.pyyaml
    p.rapidfuzz
    p.requests
    p.scikit-learn
    p.scipy
    p.sentencepiece
    p.six
    p.soundfile
    p.soxr
    p.sqlglot
    p.sympy
    tokenizers
    transformers
    p.umap-learn
    p.waitress
    p.wn
    p.zstandard
  ]);
  appDir = "$out/share/audiomuse-ai";
  mkRole = name: role: ''
    makeWrapper ${python}/bin/python "$out/bin/${name}" \
      --add-flags "${appDir}/native-build/linux/launcher.py --role=${role}" \
      --chdir "${appDir}" \
      --prefix PYTHONPATH : "${appDir}:${appDir}/native-build" \
      --set-default FPCALC ${lib.getExe chromaprint} \
      --set-default HF_HOME ${audiomuse-ai-models}/model/huggingface \
      --set-default LYRICS_MODEL_DIR ${audiomuse-ai-models}/model \
      --set-default EMBEDDING_MODEL_PATH ${audiomuse-ai-models}/model/musicnn_embedding.onnx \
      --set-default PREDICTION_MODEL_PATH ${audiomuse-ai-models}/model/musicnn_prediction.onnx \
      --set-default CLAP_AUDIO_MODEL_PATH ${audiomuse-ai-models}/model/model_epoch_36.onnx \
      --set-default CLAP_TEXT_MODEL_PATH ${audiomuse-ai-models}/model/clap_text_model.onnx \
      --set-default CLAP_SAE_ENCODER_PATH ${audiomuse-ai-models}/model/dclap_sae_k20_d1024_best_encoder.onnx \
      --set-default CLAP_SAE_MODEL_PATH ${audiomuse-ai-models}/model/dclap_sae_k20_d1024_best_decoder.onnx \
      --set-default CLAP_SAE_CONCEPTS_PATH ${appDir}/dclap_sae_concepts.json \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --set PYTHONUNBUFFERED 1
  '';
in
python313Packages.buildPythonApplication (_finalAttrs: {
  pname = "audiomuse-ai";
  inherit (appSource) version;

  src = appSourcePath;

  strictDeps = true;
  format = "other";
  dontBuild = true;
  # The executables are makeWrapper shell launchers around the composed Python
  # environment, not Python scripts for the Python hook to rewrite.
  dontWrapPythonPrograms = true;
  nativeBuildInputs = [ makeWrapper ];

  postPatch = builtins.readFile ./scripts/post-patch.sh;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit appDir;
        mkRole_audiomuse_ai_web_flask = mkRole "audiomuse-ai-web" "flask";
        mkRole_audiomuse_ai_worker_high_worker_high = mkRole "audiomuse-ai-worker-high" "worker-high";
        mkRole_audiomuse_ai_worker_default_worker_default = mkRole "audiomuse-ai-worker-default" "worker-default";
        mkRole_audiomuse_ai_maintenance_maintenance = mkRole "audiomuse-ai-maintenance" "maintenance";
        mkRole_audiomuse_ai_control_restart_listener = mkRole "audiomuse-ai-control" "restart-listener";
      }
    }
  '';

  passthru = {
    applicationSource = appSourcePath;
    models = audiomuse-ai-models;
    pythonEnvironment = python;
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
    upstreamRevision = appSource.rev;
  };

  meta = {
    description = "Self-hosted music discovery and sonic analysis for media servers";
    homepage = "https://github.com/NeptuneHub/AudioMuse-AI";
    changelog = "https://github.com/NeptuneHub/AudioMuse-AI/releases/tag/${appSource.tag}";
    license = lib.licenses.agpl3Only;
    mainProgram = "audiomuse-ai-web";
    # pynndescent is disabled on aarch64-linux in the pinned Nixpkgs revision.
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
