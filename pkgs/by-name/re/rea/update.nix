{
  writeShellApplication,
  python3,
  nix,
  git,
  patch,
  prefetch-npm-deps,
  cacert,
  path,
}:
writeShellApplication {
  name = "update-rea";
  runtimeInputs = [
    (python3.withPackages (packages: [ packages.sigstore ]))
    nix
    git
    patch
    prefetch-npm-deps
  ];
  runtimeEnv = {
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NIXPKGS_UPDATE_SOURCE = "${path}";
  };
  text = ''
    exec python3 ${./run_update.py} --updater-name rea "$@"
  '';
}
