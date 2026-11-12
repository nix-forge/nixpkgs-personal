# shellcheck shell=bash
runHook preInstallCheck
@checkArtworkCommand@
runHook postInstallCheck
