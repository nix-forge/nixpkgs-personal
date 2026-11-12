let
  licenses = import ../scripts/license-metadata.nix;
  free = {
    shortName = "Free";
    free = true;
  };
  unfree = {
    shortName = "Restricted";
    free = false;
  };
  simple = free // {
    licenseType = "simple";
    spdxId = "MIT";
  };
  compound = operator: children: {
    licenseType = "compound";
    inherit operator;
    licenses = children;
  };
  choice = compound "OR" [
    simple
    unfree
  ];
  required = compound "AND" [
    choice
    unfree
  ];
  exception = {
    licenseType = "exception";
    operator = "WITH";
    license = simple;
    exception = free;
  };
  later = {
    licenseType = "plus";
    operator = "+";
    license = simple;
  };
  cases = {
    legacy =
      licenses.describe free == {
        name = "Free";
        url = "";
        free = true;
      };
    choice = (licenses.describe choice).name == "MIT OR Restricted" && licenses.isFree choice;
    required =
      (licenses.describe required).name == "(MIT OR Restricted) AND Restricted"
      && !licenses.isFree required;
    exception = (licenses.describe exception).name == "MIT WITH Free" && licenses.isFree exception;
    later = (licenses.describe later).name == "MIT+" && licenses.isFree later;
    invalid = builtins.all (x: !licenses.valid x) [
      null
      "MIT"
      { }
      (compound "XOR" [ simple ])
      (compound "AND" [ ])
      (compound "OR" [ { } ])
    ];
  };
in
assert builtins.all (x: x) (builtins.attrValues cases);
cases
