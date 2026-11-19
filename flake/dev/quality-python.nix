# Use the same declared imports for developer commands and type-check hooks.
{ pkgs }:
pkgs.python3.withPackages (
  ps: with ps; [
    defusedxml
    httpx
    fonttools
    lxml
    packaging
    pillow
    pyyaml
    sigstore
    sqlalchemy
    uharfbuzz
    websocket-client
    (pkgs.callPackage ../../pkgs/by-name/no/notification-process/package.nix { })
  ]
)
