{
  lib,
  fetchFromGitHub,
  python313Packages,
  huggingfaceHub,
  safetensors,
  tokenizers,
}:
python313Packages.transformers.overridePythonAttrs (old: rec {
  version = "4.57.6";
  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "transformers";
    tag = "v${version}";
    hash = "sha256-a78ornUAYlOpr30iFdq1oUiWQTm6GeT0iq8ras5i3DQ=";
  };

  postPatch = (old.postPatch or "") + ''
    substituteInPlace src/transformers/dependency_versions_table.py \
      --replace-fail 'tokenizers>=0.22.0,<=0.23.0' 'tokenizers>=0.22.0,<=0.23.1'
  '';
  dependencies = [
    python313Packages.filelock
    huggingfaceHub
    python313Packages.numpy
    python313Packages.packaging
    python313Packages.pyyaml
    python313Packages.regex
    python313Packages.requests
    safetensors
    tokenizers
    python313Packages.tqdm
  ];
  optional-dependencies = { };
  pythonRelaxDeps = [ "tokenizers" ];
  doCheck = false;
  nativeCheckInputs = [ ];
  pythonImportsCheck = [ "transformers" ];

  meta = {
    description = "Machine-learning model and tokenizer library";
    homepage = "https://github.com/huggingface/transformers";
    changelog = "https://github.com/huggingface/transformers/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
