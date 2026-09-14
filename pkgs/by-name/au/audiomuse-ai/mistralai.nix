{
  lib,
  fetchFromGitHub,
  python313Packages,
}:
python313Packages.buildPythonPackage rec {
  pname = "mistralai";
  version = "1.12.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mistralai";
    repo = "client-python";
    tag = "v${version}";
    hash = "sha256-gkxjEVLsW8mC94lk0DwC7KWJDskMUMl3AqCjEvmyEGg=";
  };

  build-system = [ python313Packages.hatchling ];
  dependencies = with python313Packages; [
    eval-type-backport
    httpx
    invoke
    opentelemetry-api
    opentelemetry-exporter-otlp-proto-http
    opentelemetry-sdk
    pydantic
    python-dateutil
    pyyaml
    typing-inspection
  ];

  # Upstream's test group requires every optional integration, including the
  # MCP agent stack. AudioMuse uses only the core client. Keep an import check
  # here and exercise the client through AudioMuse's install check instead.
  doCheck = false;
  pythonImportsCheck = [ "mistralai" ];

  meta = {
    description = "Python client library for the Mistral AI platform";
    homepage = "https://github.com/mistralai/client-python";
    changelog = "https://github.com/mistralai/client-python/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
