{
  writeShellApplication,
  python3,
  nix,
  nixfmt,
  cacert,
  path,
}:
writeShellApplication {
  name = "update-chatgpt-latest";
  runtimeInputs = [
    (python3.withPackages (ps: [ ps.defusedxml ]))
    nix
    nixfmt
  ];
  runtimeEnv = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIXPKGS_UPDATE_SOURCE = "${path}";
  };
  text = ''
    exec python3 ${./run_update.py} --updater-name chatgpt-latest "$@"
  '';
}
