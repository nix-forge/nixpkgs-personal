# shellcheck shell=bash
# shellcheck disable=SC2154
runHook preInstall
install -Dm755 target/*/release/rift "$out/bin/rift"
install -Dm755 target/*/release/rift-cli "$out/bin/rift-cli"
install -Dm644 rift.default.toml "$out/share/doc/rift/rift.default.toml"
install -Dm644 LICENSE "$out/share/doc/rift/LICENSE"
runHook postInstall
