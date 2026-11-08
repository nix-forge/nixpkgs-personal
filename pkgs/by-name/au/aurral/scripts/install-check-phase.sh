# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
cd "$out/libexec/aurral" || exit
node @nativeCheck@
node @lidarr_metadata_test_mts@ "$out/libexec/aurral"
node @listenbrainz_discover_test_mts@ "$out/libexec/aurral"
node @listenbrainz_connect_test_mts@ "$out/libexec/aurral"
node @native_audio_tags_test_mts@ "$out/libexec/aurral"
node @artist_identity_test_mts@ "$out/libexec/aurral"
node @canonical_artwork_test_mts@ "$out/libexec/aurral"
node @navidrome_managed_library_test_mts@ "$out/libexec/aurral"
node @matcher_runtime_test_mts@ "$out/libexec/aurral"
test -f frontend/dist/index.html
test -f backend/server.ts
runHook postInstallCheck
