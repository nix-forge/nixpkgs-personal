# Render package hook text for native syntax checks, without foreign toolchains.
# Production recipes still use Nixpkgs replaceVars. Match its ordered replacements,
# unused-key failures and explicit-null exception to the unresolved-marker check.
{ lib }:
let
  isTemplate = path: builtins.match ".*\\.(sh|sh\\.in|py)" path != null;
  stripRuntimeDependencies =
    value:
    if value == null then
      null
    else
      let
        text = if builtins.isPath value then "${value}" else toString value;
      in
      builtins.appendContext (builtins.unsafeDiscardStringContext text) (
        lib.filterAttrs (path: _: isTemplate path) (builtins.getContext text)
      );
in
source: replacements:
let
  original = builtins.readFile source;
  names = builtins.attrNames replacements;
  # Validation-only rendering; production continues to use replaceVars.
  rendered = lib.foldl' (
    text: name:
    let
      marker = "@${name}@";
      value = replacements.${name};
    in
    assert lib.assertMsg (lib.hasInfix marker text) "Unused template replacement: ${name}";
    builtins.replaceStrings
      [ marker ]
      [ (if value == null then marker else stripRuntimeDependencies value) ]
      text
  ) original names;
  markers = lib.filter builtins.isList (builtins.split "@([a-zA-Z_][0-9A-Za-z_'-]*)@" rendered);
  unexpected = lib.filter (
    match:
    let
      name = builtins.head match;
    in
    !(builtins.hasAttr name replacements && replacements.${name} == null)
  ) markers;
in
assert lib.assertMsg (unexpected == [ ]) "Unsubstituted template replacement";
builtins.toFile (baseNameOf (builtins.unsafeDiscardStringContext (toString source))) rendered
