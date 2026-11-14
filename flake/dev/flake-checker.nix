# Backport https://github.com/NixOS/nixpkgs/commit/330030f95450638670347912ffbce5694effc09d.
# Retire when the selected flake-checker recipe supplies pkg-config and zstd.
{ pkgs }:
let
  package = pkgs.flake-checker;
  fixed =
    builtins.elem pkgs.pkg-config (package.nativeBuildInputs or [ ])
    && builtins.elem pkgs.zstd (package.buildInputs or [ ]);
in
if fixed then
  package
else
  assert package.version == "0.2.15";
  package.overrideAttrs (old: {
    nativeBuildInputs = pkgs.lib.unique ((old.nativeBuildInputs or [ ]) ++ [ pkgs.pkg-config ]);
    buildInputs = pkgs.lib.unique ((old.buildInputs or [ ]) ++ [ pkgs.zstd ]);
  })
