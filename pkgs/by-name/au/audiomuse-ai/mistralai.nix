{
  lib,
  stdenv,
  fetchFromGitHub,
  python313Packages,
  source ? import ./source.nix,
}:
let
  upstream = source.python.mistralai;
in
python313Packages.buildPythonPackage {
  pname = "mistralai";
  inherit (upstream) version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mistralai";
    repo = "client-python";
    inherit (upstream) rev hash;
  };

  build-system = [ python313Packages.hatchling ];
  dependencies = with python313Packages; [
    eval-type-backport
    httpx
    opentelemetry-api
    opentelemetry-exporter-otlp-proto-http
    opentelemetry-sdk
    pydantic
    python-dateutil
    pyyaml
    typing-inspection
  ];

  # Invoke is used by upstream's repository-level tasks.py, which is not
  # shipped in the SDK wheel. It is not a runtime dependency. Remove that
  # metadata entry rather than relaxing its version bound or disabling the
  # runtime dependency check. This also applies when the SDK pin is updated.
  pythonRemoveDeps = [ "invoke" ];

  # Upstream's test group requires every optional integration, including the
  # MCP agent stack. AudioMuse uses only the core client. Keep an import check
  # here; this does not establish authenticated client or inference behavior.
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  pythonImportsCheck = [ "mistralai" ];

  meta = {
    description = "Python client library for the Mistral AI platform";
    homepage = "https://github.com/mistralai/client-python";
    changelog = "https://github.com/mistralai/client-python/releases/tag/v${upstream.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
