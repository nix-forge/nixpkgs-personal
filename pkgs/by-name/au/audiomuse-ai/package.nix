{
  lib,
  callPackage,
  stdenv,
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
  safetensors = python313Packages.safetensors.overridePythonAttrs (_old: {
    doCheck = false;
    nativeCheckInputs = [ ];
    optional-dependencies = { };
  });
  tokenizers =
    (python313Packages.tokenizers.override { huggingface-hub = huggingfaceHub; }).overridePythonAttrs
      (_old: {
        doCheck = false;
        nativeCheckInputs = [ ];
      });
  transformers = callPackage ./transformers.nix {
    inherit
      source
      huggingfaceHub
      safetensors
      tokenizers
      ;
  };
  # Narwhals includes every optional dataframe backend in its Nixpkgs check
  # closure. One of those reaches a terminal-width documentation test in
  # inline-snapshot that fails non-interactively. AudioMuse reaches Narwhals
  # only through scikit-learn, so omit those optional checks while retaining
  # scikit-learn's own test suite. Targeted overrides avoid evaluating a second
  # recursive Python package set.
  narwhals = python313Packages.narwhals.overridePythonAttrs (_old: {
    doCheck = false;
    nativeCheckInputs = [ ];
  });
  scikitLearn = python313Packages.scikit-learn.override { inherit narwhals; };
  pynndescent = python313Packages.pynndescent.override { scikit-learn = scikitLearn; };
  librosa = python313Packages.librosa.override { scikit-learn = scikitLearn; };
  umapLearn = python313Packages.umap-learn.override {
    inherit pynndescent;
    scikit-learn = scikitLearn;
  };
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
    librosa
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
    scikitLearn
    p.scipy
    p.sentencepiece
    p.six
    p.soundfile
    p.soxr
    p.sqlglot
    p.sympy
    tokenizers
    transformers
    umapLearn
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

  postPatch = ''
    substituteInPlace service_roles.py \
      --replace-fail "FLASK_BIND_HOST = '0.0.0.0'" \
        "FLASK_BIND_HOST = os.environ.get('AUDIOMUSE_HOST', '127.0.0.1')" \
      --replace-fail "FLASK_BIND_PORT = 8000" \
        "FLASK_BIND_PORT = int(os.environ.get('AUDIOMUSE_PORT', '8000'))"
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p \
      ${appDir}/native-build/linux \
      ${appDir}/native-build/native_common \
      "$out/bin" \
      "$out/share/doc/audiomuse-ai"
    cp -R \
      ./*.py dclap_sae_concepts.json genre_subgenre.json \
      mood_centroids_real_080_clap.json \
      error lyrics plugin query static taskqueue tasks templates \
      ${appDir}/
    cp native-build/linux/{__init__,launcher}.py ${appDir}/native-build/linux/
    cp native-build/native_common/{__init__,frozen_children}.py \
      ${appDir}/native-build/native_common/
    install -Dm644 LICENSE "$out/share/doc/audiomuse-ai/LICENSE"
    ${mkRole "audiomuse-ai-web" "flask"}
    ${mkRole "audiomuse-ai-worker-high" "worker-high"}
    ${mkRole "audiomuse-ai-worker-default" "worker-default"}
    ${mkRole "audiomuse-ai-maintenance" "maintenance"}
    ${mkRole "audiomuse-ai-control" "restart-listener"}
    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  nativeInstallCheckInputs = [ python ];
  installCheckPhase = ''
    runHook preInstallCheck
    export DATABASE_URL=
    cd ${appDir}
    python -m compileall -q .
    for program in "$out"/bin/audiomuse-ai-*; do
      head -n 1 "$program" | grep -q '/bin/bash'
    done
    python - <<'PY'
    import sys

    sys.path.insert(0, "native-build")
    import flask
    import google.genai
    import importlib.metadata
    import huggingface_hub
    import librosa
    import mistralai
    import mutagen
    import numkong
    import onnxruntime
    import psycopg2
    import sentencepiece
    import tokenizers
    import transformers
    import app_auth
    import numeric_bootstrap
    import service_roles
    from packaging.requirements import Requirement
    from packaging.version import Version
    from transformers.dependency_versions_table import deps
    from linux import launcher

    package_version = importlib.metadata.version
    assert package_version("google-genai") == "${source.python.googleGenai.version}"
    assert package_version("mistralai") == "${source.python.mistralai.version}"
    assert package_version("transformers") == "${source.python.transformers.version}"
    assert package_version("huggingface-hub") == "${source.python.huggingfaceHub.version}"
    tokenizers_requirement = Requirement(deps["tokenizers"])
    assert deps["tokenizers"] == "${source.python.transformers.tokenizersRequirement}"
    assert tokenizers_requirement.specifier.contains(
        package_version("tokenizers"), prereleases=True
    )
    assert Version(package_version("tokenizers")) >= Version("0.22.0")
    assert service_roles.ROLE_FLASK == "flask"
    assert launcher.WEB_URL == "http://127.0.0.1:8000"
    PY
    runHook postInstallCheck
  '';

  passthru = {
    applicationSource = appSourcePath;
    models = audiomuse-ai-models;
    pythonEnvironment = python;
    updateScript = [
      "python3"
      "pkgs/by-name/au/audiomuse-ai/update.py"
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
