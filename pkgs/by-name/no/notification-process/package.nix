{ lib, python3Packages }:
python3Packages.buildPythonPackage {
  pname = "notification-process";
  version = "0.1.0";
  pyproject = true;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
      ./LICENSE
      ./test_notifications.py
      ./fixtures
    ];
  };
  build-system = [ python3Packages.setuptools ];
  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    python3Packages.pytest-timeout
  ];
  pytestFlags = [
    "--timeout=30"
    "--timeout-method=thread"
    "test_notifications.py"
  ];
  pythonImportsCheck = [ "notification_process" ];
  meta = {
    description = "Owned commands with blocking POSIX exit and pipe notifications";
    homepage = "https://github.com/nix-forge/nixpkgs-personal/tree/main/pkgs/by-name/no/notification-process";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = [ ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
