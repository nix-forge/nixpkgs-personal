{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python313Packages,
  makeWrapper,
  runCommand,
  curl,
  cacert,
}:
let
  source = import ./source.nix;
  py = python313Packages;
  # PostHog 7.x's optional MCP test integration requires MCP <2. Preserve its
  # complete upstream suite using Nixpkgs' maintained compatibility package.
  enginePosthog = (py.posthog.override { mcp = py.mcp_1 or py.mcp; }).overridePythonAttrs (previous: {
    # Nix's 64 MiB thread stacks inflate this thread-heavy suite's virtual
    # address space enough to deny real forks despite spare physical memory.
    # Use the normal Linux soft stack limit before Python starts; retain all
    # tests, thread counts, hard limits and compiler parallelism.
    preCheck = (previous.preCheck or "") + ''
      ulimit -S -s 8192
    '';
  });
  # The engine explicitly requires Pydantic AI 1.x. Keep both halves on the
  # version in engine/uv.lock instead of taking Nixpkgs' incompatible 2.x.
  aiSource = fetchFromGitHub {
    owner = "pydantic";
    repo = "pydantic-ai";
    tag = "v${source.pydanticAi.version}";
    inherit (source.pydanticAi) hash;
  };
  graph = py.pydantic-graph.overridePythonAttrs {
    inherit (source.pydanticAi) version;
    src = aiSource;
    sourceRoot = "source/pydantic_graph";
    dependencies = with py; [
      httpx
      logfire-api
      pydantic
      typing-inspection
    ];
  };
  # Keep AI 1.x's <0.1 prices API at the release lock's selected version.
  prices = py.genai-prices.overridePythonAttrs {
    inherit (source.genaiPrices) version;
    src = fetchFromGitHub {
      owner = "pydantic";
      repo = "genai-prices";
      tag = "v${source.genaiPrices.version}";
      inherit (source.genaiPrices) hash;
    };
    sourceRoot = "source/packages/python";
    build-system = [ py.uv-build ];
    # uv 0.12 keeps the build-backend configuration compatible with 0.8+;
    # only its major/minor upper bound needs widening for the incoming builder.
    postPatch = ''
      substituteInPlace pyproject.toml \
        --replace-fail 'uv_build>=0.8.10,<0.12' 'uv_build>=0.8.10,<0.13'
    '';
  };
  ai = py.pydantic-ai-slim.overridePythonAttrs {
    inherit (source.pydanticAi) version;
    src = aiSource;
    sourceRoot = "source/pydantic_ai_slim";
    dependencies = with py; [
      prices
      griffelib
      httpx
      opentelemetry-api
      graph
      pydantic
      typing-inspection
    ];
  };
  # Use maintained Nixpkgs dependencies outside the incompatible Pydantic AI
  # major version. Some are below engine/pyproject.toml's dependency-group
  # minima; the README records the tested versions and behavioral coverage.
  python = py.python.withPackages (
    _: with py; [
      ai
      anthropic
      cryptography
      fastapi
      httpx
      openai
      opentelemetry-sdk
      pgvector
      enginePosthog
      psycopg
      psycopg-pool
      pydantic
      pydantic-settings
      python-dotenv
      sqlite-vec
      tiktoken
      uvicorn
      websockets
    ]
  );
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "stirling-pdf-engine";
  inherit (source) version;
  strictDeps = true;
  src = fetchFromGitHub {
    owner = "Stirling-Tools";
    repo = "Stirling-PDF";
    tag = "v${source.version}";
    inherit (source) hash;
  };
  sourceRoot = "source/engine";
  nativeBuildInputs = [
    makeWrapper
    python
  ];
  nativeCheckInputs = [ py.pytest ];
  patches = [ ./writable-state.patch ];
  # Preserve deterministic math and privacy routing before model dispatch.
  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        math_intent_patch = "${./math-intent.patch}";
        privacy_report_routing_patch = "${./privacy-report-routing.patch}";
      }
    }
  '';
  buildPhase = builtins.readFile ./scripts/build-phase.sh;
  doCheck = true;
  checkPhase = builtins.readFile ./scripts/check-phase.sh;
  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit python; }}
  '';
  passthru.tests.posthog = enginePosthog;
  passthru.tests.runtime =
    runCommand "stirling-pdf-engine-runtime" { nativeBuildInputs = [ curl ]; }
      ''
        source ${
          replaceVars ./scripts/stirling-pdf-engine-runtime.sh {
            inherit cacert;
            mainExecutable = lib.getExe finalAttrs.finalPackage;
          }
        }
      '';
  meta = {
    description = "Native Python AI document engine for Stirling PDF";
    homepage = "https://github.com/Stirling-Tools/Stirling-PDF";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    mainProgram = "stirling-pdf-engine";
    platforms = lib.platforms.linux;
  };
})
