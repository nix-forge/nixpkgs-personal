{ pkgs, appimageRuntime }:
pkgs.buildPackages.runCommand "craft-launcher-appimage-runtime-check"
  {
    nativeBuildInputs = [
      pkgs.buildPackages.python3
      pkgs.buildPackages.patch
    ];
  }
  ''
    python3 ${./scripts/test_libgomp_device_uid.py} \
      --source ${pkgs.gcc.cc.src} \
      --patch ${./gcc-libgomp-device-uid-buffer.patch} \
      --fixture ${./scripts/device-uid-regression.c} \
      --compiler ${pkgs.buildPackages.stdenv.cc}/bin/cc
    python3 ${./scripts/check_runtime_perl.py} \
      --tool ${(appimageRuntime.targetXMLTwig or pkgs.perlPackages.XMLTwig)}/bin/xml_grep \
      --interpreter ${pkgs.perl}/bin/perl \
      --elf-machine ${if pkgs.stdenv.hostPlatform.isAarch64 then "183" else "62"} ${
        pkgs.lib.optionalString (
          pkgs.stdenv.buildPlatform.system != pkgs.stdenv.hostPlatform.system
        ) "--reject-tool ${pkgs.perlPackages.XMLTwig}/bin/xml_grep"
      }
    touch "$out"
  ''
