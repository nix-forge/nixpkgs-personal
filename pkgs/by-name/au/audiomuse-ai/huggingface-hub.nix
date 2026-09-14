{
  lib,
  fetchFromGitHub,
  python313Packages,
}:
python313Packages.huggingface-hub.overridePythonAttrs (_old: rec {
  version = "0.36.2";
  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "huggingface_hub";
    tag = "v${version}";
    hash = "sha256-cUp5Mm8vgJI/0N/9inQVedGWRde8lioduFoccq6b7UE=";
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
  doCheck = false;
  nativeCheckInputs = [ ];
  pythonImportsCheck = [ "huggingface_hub" ];

  meta = {
    description = "Client library for the Hugging Face Hub";
    homepage = "https://github.com/huggingface/huggingface_hub";
    changelog = "https://github.com/huggingface/huggingface_hub/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
