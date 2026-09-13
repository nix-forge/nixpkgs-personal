{
  lib,
  meson,
  ninja,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "steam-cef-scale-override";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./steam-cef-scale-override.c
      ./test-libcef.c
      ./test-helper.c
      ./meson.build
      ./meson.options
      ./check-mock.sh
      ./check-elf.sh
      ./LICENSE
      ./README.md
    ];
  };
  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
  ];
  # Meson's release build type implies -O3. Keep the package's reviewed -O2
  # policy while expressing the remaining release settings as built-in options.
  mesonBuildType = "custom";
  mesonFlags = [
    "-Db_ndebug=true"
    "-Doptimization=2"
    "-Dtests=true"
  ];

  doCheck = true;
  postCheck = ''
    productionBuildDir="$PWD"

    # Exercise Meson's sanitizer configuration separately so the installed
    # release target retains undefined-symbol rejection and release settings.
    meson setup "$NIX_BUILD_TOP/sanitized-build" "$NIX_BUILD_TOP/$sourceRoot" \
      --buildtype=custom \
      -Dauto_features=enabled \
      -Db_asneeded=false \
      -Ddebug=true \
      -Db_lundef=false \
      -Db_ndebug=false \
      -Db_sanitize=address,undefined \
      -Doptimization=1 \
      -Dtests=true \
      -Dwrap_mode=nodownload
    meson compile -C "$NIX_BUILD_TOP/sanitized-build" -j "$NIX_BUILD_CORES"
    meson test -C "$NIX_BUILD_TOP/sanitized-build" \
      -j "$NIX_BUILD_CORES" --no-rebuild --print-errorlogs

    cd "$productionBuildDir"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    bash ../check-elf.sh "$out/lib/libsteam-cef-scale-override.so"

    runHook postInstallCheck
  '';

  meta = {
    description = "Process-scoped CEF scale override for Steam's desktop UI";
    homepage = "https://github.com/nix-forge/nixpkgs-personal";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
