# shellcheck shell=bash
# shellcheck disable=SC2154
runHook preInstall
install -Dm755 @unwrapped@/bin/rift "$out/Applications/Rift.app/Contents/MacOS/rift"
install -Dm755 @unwrapped@/bin/rift-cli "$out/bin/rift-cli"
install -Dm644 @unwrapped@/share/doc/rift/rift.default.toml "$out/share/doc/rift/rift.default.toml"
install -Dm644 @unwrapped@/share/doc/rift/LICENSE "$out/share/doc/rift/LICENSE"
cp @infoPlist@ "$out/Applications/Rift.app/Contents/Info.plist"
ln -s "$out/Applications/Rift.app/Contents/MacOS/rift" "$out/bin/rift"
rcodesign sign "$out/Applications/Rift.app"
rcodesign sign --binary-identifier rift-cli "$out/bin/rift-cli"
runHook postInstall
