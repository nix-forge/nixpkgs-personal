# Stirling PDF engine

Builds the Python engine from the Stirling PDF release source. The executable
`stirling-pdf-engine` runs Uvicorn and accepts its command-line options, including
`--host` and `--port`. It does not run Docker, Podman, pip, or uv at runtime.

The upstream `.env` supplies application defaults. Override them using process
environment variables. `STIRLING_ENGINE_DATA_DIR` selects writable state, defaulting
to `~/.local/share/stirling-pdf-engine`. The default database is `rag.db` in that
directory. An absolute `STIRLING_DOCUMENTS_SQLITE_PATH` takes precedence for the
database alone. The encrypted configuration cache stays in the state directory.
Keep that directory persistent if the configuration cache or documents must survive
service restarts.

Pydantic AI and Pydantic Graph are built from source at the version recorded in
`engine/uv.lock`, because the engine requires their 1.x API. GenAI Prices is
also pinned to the lock's 0.0.73 release to satisfy that API's `<0.1` constraint.
Other dependencies
come from Nixpkgs. PostHog's optional MCP test integration uses the maintained
MCP 1 compatibility package where available, matching the SDK's `<2` test
requirement. Its full inherited test suite remains enabled and is exposed as
`passthru.tests.posthog`. The recipe exercises upstream authentication, encrypted config
cache, document storage, and API tests. Its runtime passthru test starts the
installed command and checks health and SQLite initialization without an external
model provider.

The tested Nixpkgs dependency set supplies Pydantic 2.13.4, Pydantic Settings
2.12.0, python-dotenv 1.2.2, and Uvicorn 0.51.0. These are below the engine's
declared dependency-group minima of 2.13.5, 2.15.0, 1.2.3, and 0.52.3 respectively.
The recipe selects 69 upstream tests and checks installed-service startup.
Those checks establish the exercised behavior, not compatibility with every
external model provider. Keep these maintained Nixpkgs packages unless a failing
check or runtime incompatibility requires a source override.

The engine has its own restrictive
[Stirling PDF User License](https://github.com/Stirling-Tools/Stirling-PDF/blob/v3.3.0/engine/LICENSE),
not the repository's MIT license. The recipe marks it unfree and installs the
notice. Source availability does not remove the upstream restrictions on
production use, modification, or redistribution.

Updates are manual. Review the engine license and Python dependency group, update
`source.nix` and the paired Pydantic AI pins together, then run the build and runtime
test. The recipe also carries deterministic math-intent and privacy-report routing
patches, previously applied by the consuming host. Patches apply from the upstream
`engine` directory.
