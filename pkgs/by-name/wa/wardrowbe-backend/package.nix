{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPypi,
  python3,
  makeWrapper,
  stdenv,
  valkey,
  postgresql,
}:
let
  source = import ./source.nix;
  # Follow the incoming nixpkgs Python set to reuse its tested, cached packages.
  # ARQ is not yet in nixpkgs. Keep its compatible Redis client scoped to this
  # environment; retire both local recipes when upstream provides ARQ.
  python = python3.override {
    packageOverrides =
      final: prev:
      # Upstream Wardrowbe 1.11 requires SQLAlchemy 2.1. Keep the source-backed
      # version scoped here until the incoming Python set catches up, and retain
      # the upstream package's build system, dependencies and test suite.
      {
        sqlalchemy =
          if lib.versionOlder prev.sqlalchemy.version source.sqlalchemyVersion then
            prev.sqlalchemy.overridePythonAttrs (
              old:
              let
                series = lib.replaceStrings [ "." ] [ "" ] (lib.versions.majorMinor source.sqlalchemyVersion);
                # SQLAlchemy 2.1's source requires Cython >=3.3. Keep this compiler
                # scoped to SQLAlchemy's build system, not the Python package set.
                cythonCompiler =
                  if lib.versionOlder prev.cython.version source.cythonVersion then
                    prev.cython.overridePythonAttrs (cythonOld: {
                      version = source.cythonVersion;
                      src = fetchPypi {
                        pname = "cython";
                        version = source.cythonVersion;
                        hash = source.cythonHash;
                      };
                      # Cython 3.3.1 includes the unknown-global-annotation fix
                      # and pure_pxd regression from upstream PR 7970. Drop only
                      # that inherited 3.3.0 backport when selecting newer source.
                      patches = builtins.filter (
                        patch:
                        !(
                          lib.versionAtLeast source.cythonVersion "3.3.1"
                          && builtins.isAttrs patch
                          && builtins.elem "https://github.com/cython/cython/pull/7970.patch" (
                            patch.urls or [ (patch.url or "") ]
                          )
                        )
                      ) (cythonOld.patches or [ ]);
                      # Compile and run the upstream compiler-source fixture,
                      # including its typed .pxd / unknown Final case.
                      doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
                      postInstallCheck = (cythonOld.postInstallCheck or "") + ''
                        test -f tests/run/pure_pxd.srctree
                        ${python3.interpreter} runtests.py -j"$NIX_BUILD_CORES" --no-code-style pure_pxd
                      '';
                      meta = cythonOld.meta // {
                        changelog = "https://github.com/cython/cython/blob/${source.cythonVersion}/CHANGES.rst";
                      };
                    })
                  else
                    prev.cython;
                isCython = input: (input.pname or null) == "cython";
              in
              assert builtins.length (builtins.filter isCython old.build-system) == 1;
              {
                build-system = map (input: if isCython input then cythonCompiler else input) old.build-system;
                # SQLAlchemy 2.1 removed this test directory. Keep every other
                # inherited exclusion and run the actual upstream pytest hook.
                disabledTestPaths = builtins.filter (path: path != "test/ext/mypy") old.disabledTestPaths;
                version = source.sqlalchemyVersion;
                src = fetchPypi {
                  pname = "sqlalchemy";
                  version = source.sqlalchemyVersion;
                  hash = source.sqlalchemyHash;
                };
                meta = old.meta // {
                  changelog = "https://docs.sqlalchemy.org/en/${series}/changelog/changelog_${series}.html#change-${source.sqlalchemyVersion}";
                };
              }
            )
          else
            prev.sqlalchemy;
      }
      // lib.optionalAttrs (!(prev ? arq)) {
        redis = final.buildPythonPackage rec {
          pname = "redis";
          version = source.redisVersion;
          pyproject = true;
          src = fetchPypi {
            inherit pname version;
            hash = source.redisHash;
          };
          build-system = [ final.setuptools ];
          dependencies = [ final.pyjwt ];
          pythonImportsCheck = [
            "redis"
            "redis.asyncio"
          ];
          doCheck = false; # PyPI source omits the integration test suite.
        };
        arq = final.buildPythonPackage rec {
          pname = "arq";
          version = source.arqVersion;
          pyproject = true;
          src = fetchPypi {
            inherit pname version;
            hash = source.arqHash;
          };
          build-system = [ final.hatchling ];
          dependencies = with final; [
            click
            redis
            hiredis
          ];
          pythonImportsCheck = [
            "arq"
            "arq.cli"
            "arq.worker"
          ];
          doCheck = false; # Integration suite needs a running Redis server.
        };
      };
  };
  # certifi is a pure Python trust-data leaf. Select its reviewed release in
  # the application environment without changing reusable packages' build inputs.
  runtimeCertifi =
    if lib.versionOlder python.pkgs.certifi.version source.certifiVersion then
      python.pkgs.certifi.overridePythonAttrs {
        version = source.certifiVersion;
        src = fetchPypi {
          pname = "certifi";
          version = source.certifiVersion;
          hash = source.certifiHash;
        };
        # Retain env.patch and upstream tests; use the release Mozilla bundle.
        postPatch = "";
      }
    else
      python.pkgs.certifi;
  pythonEnv =
    (python.withPackages (
      ps:
      (with ps; [
        fastapi
        uvicorn
        python-multipart
        sqlalchemy
        asyncpg
        alembic
        pydantic
        pydantic-settings
        email-validator
        pyjwt
        cryptography
        httpx
        certifi
        pillow
        pillow-heif
        redis
        arq
        apscheduler
        aiosmtplib
        tenacity
        python-dateutil
        imagehash
        rembg
      ])
      ++ ps.uvicorn.optional-dependencies.standard
      ++ ps.sqlalchemy.optional-dependencies.asyncio
    )).override
      {
        # Replace the flattened module, including its distribution metadata, once.
        # All HTTP clients importing certifi see the selected application module.
        requiredPythonModules =
          dependencies:
          let
            modules = python.pkgs.requiredPythonModules dependencies;
            isCertifi = module: (module.pname or null) == "certifi";
          in
          assert builtins.length (builtins.filter isCertifi modules) == 1;
          map (module: if isCertifi module then runtimeCertifi else module) modules;
      };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "wardrowbe-backend";
  inherit (source) version;
  strictDeps = true;
  src = fetchFromGitHub {
    owner = "Anyesh";
    repo = "wardrowbe";
    inherit (source) rev;
    inherit (source) hash;
  };
  patches = [
    ./ai-providers.patch
    ./planning.patch
  ];
  nativeBuildInputs = [ makeWrapper ];
  passthru.pythonEnvironment = pythonEnv;
  dontBuild = true;
  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit pythonEnv; }}
  '';
  doInstallCheck = true;
  passAsFile = [
    "queueSmoke"
    "providerSmoke"
    "browserAuthSmoke"
    "paginationSmoke"
  ];
  browserAuthSmoke = builtins.readFile ./browser_auth_smoke.py;
  providerSmoke = builtins.readFile ./provider_smoke.py;
  queueSmoke = builtins.readFile ./queue_smoke.py;
  paginationSmoke = builtins.readFile ./pagination_smoke.py;
  nativeInstallCheckInputs = [
    valkey
    postgresql
  ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit pythonEnv;
        checkCpuProvider = if stdenv.hostPlatform.isAarch64 then "false" else "true";
        entrypointsCheck = "${./scripts/check_entrypoints.py}";
        cpuProviderCheck = "${./scripts/check_cpu_provider.py}";
        inherit valkey;
        pythonCheck1 = "${./scripts/check_runtime_requirements.py}";

      }
    }
  '';
  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
  meta = {
    description = "Wardrowbe wardrobe planner API and background workers";
    homepage = "https://github.com/Anyesh/wardrowbe";
    changelog = "https://github.com/Anyesh/wardrowbe/releases/tag/wardrowbe-v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "wardrowbe-backend";
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
