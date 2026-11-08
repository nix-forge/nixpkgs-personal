{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPypi,
  python3,
  makeWrapper,
  ruff,
}:
let
  source = import ./source.nix;
  slskd-api = python3.pkgs.buildPythonPackage {
    pname = "slskd-api";
    version = "0.1.5";
    pyproject = true;
    src = fetchPypi {
      pname = "slskd-api";
      version = "0.1.5";
      hash = "sha256-LmWP7bnK5IVid255qS2NGOmyKzGpUl3xsO5vi5uJI88=";
    };
    build-system = [
      python3.pkgs.setuptools
      python3.pkgs.setuptools-git-versioning
    ];
    dependencies = [ python3.pkgs.requests ];
    pythonImportsCheck = [ "slskd_api" ];
  };
  python = python3.withPackages (ps: [
    ps.music-tag
    ps.pyarr
    slskd-api
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "soularr";
  inherit (source) version;
  src = fetchFromGitHub {
    owner = "mrusse";
    repo = "soularr";
    inherit (source) rev hash;
  };
  patches = [ ./shared-client.patch ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];
  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        transfer_ownership_py = "${./transfer_ownership.py}";
      }
    }
  '';
  nativeBuildInputs = [
    makeWrapper
    python
  ];
  strictDeps = true;
  dontBuild = true;
  nativeCheckInputs = [ ruff ];
  doCheck = true;
  checkPhase = ''
    source ${
      replaceVars ./scripts/check-phase.sh {
        check_transfer_ownership_py = "${./check_transfer_ownership.py}";
        check_shared_client_py = "${./check_shared_client.py}";
      }
    }
  '';
  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit python; }}
  '';
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;
  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Acquire Lidarr wanted albums through a shared slskd client";
    homepage = "https://github.com/mrusse/soularr";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.unix;
    mainProgram = "soularr";
    maintainers = [ ];
  };
}
