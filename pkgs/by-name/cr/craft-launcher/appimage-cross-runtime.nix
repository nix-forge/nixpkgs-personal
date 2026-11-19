{
  lib,
  pkgs,
  appimage-run,
  stdenv,
}:
if stdenv.hostPlatform.isLinux && stdenv.buildPlatform.system != stdenv.hostPlatform.system then
  let
    runtimePkgs = pkgs.extend (
      _: prev:
      lib.optionalAttrs
        (
          prev.stdenv.hostPlatform.isLinux
          && prev.stdenv.buildPlatform.system != prev.stdenv.hostPlatform.system
        )
        {
          # Build-time miniperl must not remain an installed tool's interpreter.
          perlPackages = prev.perlPackages.overrideScope (
            _: perlPrev: {
              XMLTwig = perlPrev.XMLTwig.overrideAttrs (old: {
                postFixup = (old.postFixup or "") + ''
                  substituteInPlace "$out/bin/xml_grep" \
                    --replace-fail "${prev.perl.mini}/bin/perl" "${prev.perl}/bin/perl"
                '';
              });
            }
          );
          # The FHS baseline needs target GCC runtime libraries. Retain their full ABI.
          gcc =
            if lib.versions.major prev.gcc.cc.version == "16" then
              prev.gcc.override {
                cc = prev.gcc.cc.overrideAttrs (old: {
                  patches = (old.patches or [ ]) ++ [ ./gcc-libgomp-device-uid-buffer.patch ];
                });
              }
            else
              prev.gcc;
        }
    );
  in
  (appimage-run.override { inherit (runtimePkgs) appimageTools buildFHSEnv; }).overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      targetXMLTwig = runtimePkgs.perlPackages.XMLTwig;
    };
  })
else
  appimage-run
