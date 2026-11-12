# Native tooling is separate from the application and edits the caller's checkout.
{
  writeShellApplication,
  python3,
  nix,
  cacert,
  path,
  git,
  prefetch-npm-deps,
}:
writeShellApplication {
  name = "update-wardrowbe-frontend";
  runtimeInputs = [
    (python3.withPackages (p: [ p.packaging ]))
    nix
    git
    prefetch-npm-deps
  ];
  runtimeEnv = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIXPKGS_UPDATE_SOURCE = "${path}";
  };
  text = ''
    exec python3 ${./run_update.py} --updater-name wardrowbe-frontend "$@"
  '';
}
