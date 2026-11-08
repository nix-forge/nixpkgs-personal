{
  writeShellApplication,
  python3,
  nix,
  nixfmt,
  cacert,
  path,
}:
writeShellApplication {
  name = "update-codex-latest";
  runtimeInputs = [
    python3
    nix
    nixfmt
  ];
  runtimeEnv = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIXPKGS_UPDATE_SOURCE = "${path}";
  };
  text = ''
    exec python3 ${./run_update.py} --updater-name codex-latest "$@"
  '';
}
