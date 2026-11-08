# Native tooling is separate from the application and edits the caller's checkout.
{
  writeShellApplication,
  python3,
  nix,
  cacert,
  path,
  git,
}:
writeShellApplication {
  name = "update-spotify-spotx";
  runtimeInputs = [
    python3
    nix
    git
  ];
  runtimeEnv = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIXPKGS_UPDATE_SOURCE = "${path}";
  };
  text = ''
    exec python3 ${./run_update.py} --updater-name spotify-spotx "$@"
  '';
}
