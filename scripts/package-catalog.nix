# Read only public metadata. No derivation paths or package outputs are forced.
packages:
builtins.mapAttrs (
  _: systemPackages:
  builtins.mapAttrs (
    _: package:
    let
      licenses = package.meta.license or [ ];
    in
    {
      inherit (package.meta) description;
      version = package.version or "unversioned";
      homepage = package.meta.homepage or "";
      licenses = map (license: {
        name = license.spdxId or license.shortName or license.fullName;
        url = license.url or "";
        free = license.free or true;
      }) (if builtins.isList licenses then licenses else [ licenses ]);
    }
  ) systemPackages
) packages
