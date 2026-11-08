# Native tooling is separate from the application and edits the caller's checkout.
{
  writeShellApplication,
  python3,
  nix,
  cacert,
  path,
}:
writeShellApplication {
  name = "update-mattpocock-skills";
  runtimeInputs = [
    python3
    nix
  ];
  runtimeEnv = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIXPKGS_UPDATE_SOURCE = "${path}";
  };
  text = ''
    exec python3 ${./run_update.py} --updater-name mattpocock-skills "$@"
  '';
}
