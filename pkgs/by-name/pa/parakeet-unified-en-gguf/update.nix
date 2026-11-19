# Keep network/update tools outside the model's runtime closure.
{
  writeShellApplication,
  python3,
  nix,
  cacert,
}:
writeShellApplication {
  name = "update-parakeet-unified-en-gguf";
  runtimeInputs = [
    python3
    nix
  ];
  runtimeEnv.SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  text = ''
    exec python3 ${./run_update.py} --updater-name parakeet-unified-en-gguf "$@"
  '';
}
