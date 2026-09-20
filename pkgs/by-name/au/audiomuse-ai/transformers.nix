{
  lib,
  fetchFromGitHub,
  python313Packages,
  source ? import ./source.nix,
  huggingfaceHub,
  safetensors,
  tokenizers,
}:
let
  upstream = source.python.transformers;
in
python313Packages.buildPythonPackage (finalAttrs: {
  pname = "transformers";
  inherit (upstream) version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "transformers";
    inherit (upstream) rev hash;
  };

  build-system = [ python313Packages.setuptools ];

  dependencies = with python313Packages; [
    filelock
    huggingfaceHub
    numpy
    packaging
    pyyaml
    regex
    requests
    safetensors
    tokenizers
    tqdm
  ];
  optional-dependencies = { };

  # Transformers generates dependency_versions_table.py from _deps in
  # setup.py. Patch the source of truth and regenerate the derived file in the
  # same phase. This avoids coupling the recipe to Nixpkgs' generated-table
  # patch and makes an upstream layout change fail loudly.
  postPatch = ''
    substituteInPlace setup.py \
      --replace-fail '${upstream.upstreamTokenizersRequirement}' '${upstream.tokenizersRequirement}'
    python setup.py deps_table_update
    grep -Fq '"tokenizers": "${upstream.tokenizersRequirement}",' \
      src/transformers/dependency_versions_table.py
  '';

  # Nixpkgs' tokenizers is newer than Transformers' release metadata allows,
  # but the reviewed compatibility ceiling is the currently packaged 0.23.2.
  # This relaxes wheel metadata; the generated runtime table above still
  # enforces the reviewed range at import time.
  pythonRelaxDeps = [ "tokenizers" ];
  doCheck = false;
  pythonImportsCheck = [ "transformers" ];

  meta = {
    description = "Machine-learning model and tokenizer library";
    homepage = "https://github.com/huggingface/transformers";
    changelog = "https://github.com/huggingface/transformers/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
