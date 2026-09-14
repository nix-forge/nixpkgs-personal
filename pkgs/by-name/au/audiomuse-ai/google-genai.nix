{
  lib,
  fetchFromGitHub,
  python313Packages,
}:
python313Packages.google-genai.overridePythonAttrs (_old: rec {
  version = "1.57.0";
  src = fetchFromGitHub {
    owner = "googleapis";
    repo = "python-genai";
    tag = "v${version}";
    hash = "sha256-hDoiUOghzgPHfNh26Yz9gHkyiez6B2QfbboN8uc+Smc=";
  };

  doCheck = false;
  nativeCheckInputs = [ ];
  pythonImportsCheck = [ "google.genai" ];

  meta = {
    description = "Google Generative AI Python SDK";
    homepage = "https://github.com/googleapis/python-genai";
    changelog = "https://github.com/googleapis/python-genai/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
