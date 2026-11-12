# Read only public metadata. No derivation paths or package outputs are forced.
licenseMetadata: packages:
builtins.mapAttrs (
  _: systemPackages:
  builtins.mapAttrs (
    _: package:
    let
      licenses = package.meta.license or [ ];
    in
    {
      inherit (package.meta) description;
      pname = package.pname or "";
      version = package.version or "unversioned";
      homepage = package.meta.homepage or "";
      licenses = map licenseMetadata.describe (
        if builtins.isList licenses then licenses else [ licenses ]
      );
    }
  ) systemPackages
) packages
