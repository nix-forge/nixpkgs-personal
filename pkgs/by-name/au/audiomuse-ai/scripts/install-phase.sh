# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p \
  @appDir@/native-build/linux \
  @appDir@/native-build/native_common \
  "$out/bin" \
  "$out/share/doc/audiomuse-ai"
cp -R \
  ./*.py dclap_sae_concepts.json genre_subgenre.json \
  mood_centroids_real_080_clap.json \
  error lyrics plugin query static taskqueue tasks templates \
  @appDir@/
cp native-build/linux/{__init__,launcher}.py @appDir@/native-build/linux/
cp -R native-build/native_common/. @appDir@/native-build/native_common/
install -Dm644 LICENSE "$out/share/doc/audiomuse-ai/LICENSE"
@mkRole_audiomuse_ai_web_flask@
@mkRole_audiomuse_ai_worker_high_worker_high@
@mkRole_audiomuse_ai_worker_default_worker_default@
@mkRole_audiomuse_ai_maintenance_maintenance@
@mkRole_audiomuse_ai_control_restart_listener@
runHook postInstall
