{
  lib,
  fetchFromGitHub,
  python313Packages,
  source ? import ./source.nix,
}:
let
  upstream = source.python.googleGenai;
in
python313Packages.google-genai.overridePythonAttrs (_old: {
  inherit (upstream) version;
  src = fetchFromGitHub {
    owner = "googleapis";
    repo = "python-genai";
    inherit (upstream) rev hash;
  };

  doCheck = false;
  nativeCheckInputs = [ ];
  pythonImportsCheck = [ "google.genai" ];

  meta = {
    description = "Google Generative AI Python SDK";
    homepage = "https://github.com/googleapis/python-genai";
    changelog = "https://github.com/googleapis/python-genai/blob/v${upstream.version}/CHANGELOG.md";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
