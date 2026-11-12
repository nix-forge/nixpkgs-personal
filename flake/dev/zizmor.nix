# Backport https://github.com/NixOS/nixpkgs/commit/eeae8a6c12eee4f0fcbc51db7f1d61087bce79da.
# Retire this helper once the selected upstream recipe supplies system AWS-LC.
{ pkgs }:
let
  package = pkgs.zizmor;
  fixed = pkgs.lib.any (dependency: (dependency.pname or "") == "aws-lc") package.buildInputs;
in
if fixed then
  package
else
  assert package.version == "1.32.0";
  package.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.aws-lc ];
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.pkg-config ];
  })
