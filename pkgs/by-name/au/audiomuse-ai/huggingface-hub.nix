{
  lib,
  fetchFromGitHub,
  python313Packages,
  source ? import ./source.nix,
}:
let
  upstream = source.python.huggingfaceHub;
in
python313Packages.huggingface-hub.overridePythonAttrs (_old: {
  inherit (upstream) version;
  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "huggingface_hub";
    inherit (upstream) rev hash;
  };

  dependencies = with python313Packages; [
    filelock
    fsspec
    hf-xet
    packaging
    pyyaml
    requests
    tqdm
    typing-extensions
  ];
  optional-dependencies = { };
  pythonRelaxDeps = [ ];
  # The full suite needs authenticated Hub services and optional ML frameworks.
  # Retain upstream's offline validation, auth-header, path and utility cases
  # against this Transformers 4-compatible source without those service clients.
  doCheck = true;
  nativeCheckInputs = with python313Packages; [
    pytestCheckHook
    pytest-mock
    pytest-env
  ];
  enabledTestPaths = [
    "tests/test_utils_validators.py"
    "tests/test_utils_headers.py"
    "tests/test_utils_paths.py"
    "tests/test_utils_chunks.py"
    "tests/test_utils_datetime.py"
  ];
  env.HF_HUB_OFFLINE = "1";
  pythonImportsCheck = [ "huggingface_hub" ];

  meta = {
    description = "Client library for the Hugging Face Hub";
    homepage = "https://github.com/huggingface/huggingface_hub";
    changelog = "https://github.com/huggingface/huggingface_hub/releases/tag/v${upstream.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
