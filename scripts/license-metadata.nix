# Public metadata may contain legacy leaf licenses or Nixpkgs license expressions.
let
  all = predicate: xs: builtins.all predicate xs;
  any = predicate: xs: builtins.any predicate xs;
  kind = license: license.licenseType or "simple";
  valid =
    license:
    builtins.isAttrs license
    && (
      if kind license == "compound" then
        builtins.elem (license.operator or "") [
          "AND"
          "OR"
        ]
        && builtins.isList (license.licenses or null)
        && license.licenses != [ ]
        && all valid license.licenses
      else if kind license == "exception" then
        (license.operator or "") == "WITH"
        && valid (license.license or null)
        && valid (license.exception or null)
      else if kind license == "plus" then
        (license.operator or "") == "+" && valid (license.license or null)
      else
        kind license == "simple" && builtins.isBool (license.free or null)
    );
  isFree =
    license:
    assert valid license;
    if kind license == "compound" then
      (if license.operator == "OR" then any else all) isFree license.licenses
    else if kind license == "exception" then
      isFree license.license && isFree license.exception
    else if kind license == "plus" then
      isFree license.license
    else
      license.free;
  name =
    license:
    assert valid license;
    if kind license == "compound" then
      builtins.concatStringsSep " ${license.operator} " (map bracket license.licenses)
    else if kind license == "exception" then
      "${bracket license.license} WITH ${bracket license.exception}"
    else if kind license == "plus" then
      "${bracket license.license}+"
    else
      license.spdxId or license.shortName or license.fullName;
  bracket =
    license:
    if
      builtins.elem (kind license) [
        "compound"
        "exception"
      ]
    then
      "(${name license})"
    else
      name license;
in
{
  inherit valid isFree;
  describe = license: {
    name = name license;
    url = license.url or "";
    free = isFree license;
  };
}
