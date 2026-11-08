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
    pytest
    pytest-timeout
    pyyaml
    selenium
    sigstore
    sqlalchemy
    uharfbuzz
    websocket-client
    python-xlib
    (pkgs.callPackage ../../pkgs/by-name/no/notification-process/package.nix { })
  ]
)
