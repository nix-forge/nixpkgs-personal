{ lib, stdenv }:

stdenv.mkDerivation {
  pname = "steam-cef-scale-override";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./steam-cef-scale-override.c
      ./test-libcef.c
      ./test-helper.c
      ./check-mock.sh
      ./check-elf.sh
      ./LICENSE
      ./README.md
    ];
  };
  strictDeps = true;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    $CC -std=c11 -O2 -fPIC -fvisibility=hidden \
      -Wall -Wextra -Werror -Wformat=2 -Wshadow -Wstrict-prototypes \
      -Wmissing-prototypes -Wconversion -Wsign-conversion -Wpedantic \
      -shared -Wl,--no-undefined -Wl,-z,defs -Wl,-z,relro,-z,now \
      -Wl,-z,noexecstack -Wl,-soname,libsteam-cef-scale-override.so \
      steam-cef-scale-override.c -ldl -lm \
      -o libsteam-cef-scale-override.so

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    $CC -std=c11 -O2 -fPIC -Wall -Wextra -Werror -Wpedantic \
      -shared test-libcef.c -o libcef-test.so
    $CC -std=c11 -O2 -Wall -Wextra -Werror -Wpedantic \
      test-helper.c -L. -lcef-test -Wl,-rpath,"$PWD" -o steamwebhelper
    bash check-mock.sh "$PWD" "$PWD/libsteam-cef-scale-override.so"

    # Instrument every mock component. Link the interposer before the mock CEF
    # library so the executable loads ASan first without preloading a runtime
    # from a compiler-specific path. The release lane above tests LD_PRELOAD.
    mkdir sanitized
    sanitizerFlags=(
      -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined
      -fno-sanitize-recover=all
    )
    $CC -std=c11 "''${sanitizerFlags[@]}" -fPIC -fvisibility=hidden \
      -Wall -Wextra -Werror -Wformat=2 -Wshadow -Wstrict-prototypes \
      -Wmissing-prototypes -Wconversion -Wsign-conversion -Wpedantic \
      -shared steam-cef-scale-override.c -ldl -lm \
      -o sanitized/libsteam-cef-scale-override.so
    $CC -std=c11 "''${sanitizerFlags[@]}" -fPIC \
      -Wall -Wextra -Werror -Wpedantic -shared test-libcef.c \
      -o sanitized/libcef-test.so
    $CC -std=c11 "''${sanitizerFlags[@]}" -Wall -Wextra -Werror -Wpedantic \
      test-helper.c -Lsanitized -Wl,--no-as-needed \
      -lsteam-cef-scale-override -lcef-test -Wl,-rpath,"$PWD/sanitized" \
      -o sanitized/steamwebhelper
    # Shared sanitizer objects intentionally omit -z defs/--no-undefined;
    # sanitizer runtime symbols are resolved by the instrumented executable.
    ASAN_OPTIONS=halt_on_error=1:exitcode=99:detect_leaks=1 \
      UBSAN_OPTIONS=halt_on_error=1:exitcode=99:print_stacktrace=1 \
      bash check-mock.sh "$PWD/sanitized" ""

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 libsteam-cef-scale-override.so \
      "$out/lib/libsteam-cef-scale-override.so"
    install -Dm644 LICENSE "$out/share/licenses/steam-cef-scale-override/LICENSE"
    install -Dm644 README.md "$out/share/doc/steam-cef-scale-override/README.md"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    bash check-elf.sh "$out/lib/libsteam-cef-scale-override.so"

    runHook postInstallCheck
  '';

  meta = {
    description = "Process-scoped CEF scale override for Steam's desktop UI";
    homepage = "https://github.com/nix-forge/nixpkgs-personal";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
