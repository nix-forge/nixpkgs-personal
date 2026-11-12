# Native tooling is separate from the application and edits the caller's checkout.
{
  writeShellApplication,
  python3,
  nix,
  cacert,
  path,
  fontconfig,
  _7zz,
}:
writeShellApplication {
  name = "update-apple-fonts";
  runtimeInputs = [
    python3
    nix
    fontconfig
    _7zz
  ];
  runtimeEnv = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIXPKGS_UPDATE_SOURCE = "${path}";
  };
  text = ''
    exec python3 ${./run_update.py} --updater-name apple-fonts "$@"
  '';
}
