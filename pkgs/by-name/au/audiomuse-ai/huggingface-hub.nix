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
  doCheck = false;
  nativeCheckInputs = [ ];
  pythonImportsCheck = [ "huggingface_hub" ];

  meta = {
    description = "Client library for the Hugging Face Hub";
    homepage = "https://github.com/huggingface/huggingface_hub";
    changelog = "https://github.com/huggingface/huggingface_hub/releases/tag/v${upstream.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
