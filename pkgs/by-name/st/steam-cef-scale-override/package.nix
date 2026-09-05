{ lib, stdenv }:

stdenv.mkDerivation {
  pname = "steam-cef-scale-override";
  version = "1.0.0";

  src = ./.;
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
    cp steamwebhelper unrelated-cef-helper

    assert_log() {
      local expected="$1"
      local actual
      actual="$(tr '\n' '|' < "$STEAM_SCALE_TEST_LOG")"
      if [[ "$actual" != "$expected" ]]; then
        echo "expected event log '$expected', got '$actual'" >&2
        return 1
      fi
    }

    export STEAM_SCALE_TEST_LOG="$PWD/events.log"

    : > "$STEAM_SCALE_TEST_LOG"
    STEAM_SCALE_FACTOR=1.5 \
      LD_PRELOAD="$PWD/libsteam-cef-scale-override.so" \
      ./steamwebhelper
    assert_log 'initialize|scale=1.50|'

    : > "$STEAM_SCALE_TEST_LOG"
    STEAM_SCALE_FACTOR=1.5 \
      LD_PRELOAD="$PWD/libsteam-cef-scale-override.so" \
      ./unrelated-cef-helper
    assert_log 'initialize|'

    : > "$STEAM_SCALE_TEST_LOG"
    STEAM_SCALE_FACTOR='1.5trailing' \
      LD_PRELOAD="$PWD/libsteam-cef-scale-override.so" \
      ./steamwebhelper 2> invalid-scale.log
    assert_log 'initialize|'
    grep -Fq 'ignoring invalid STEAM_SCALE_FACTOR' invalid-scale.log

    : > "$STEAM_SCALE_TEST_LOG"
    if STEAM_SCALE_TEST_INIT_FAIL=1 STEAM_SCALE_FACTOR=1.5 \
      LD_PRELOAD="$PWD/libsteam-cef-scale-override.so" \
      ./steamwebhelper; then
      echo 'the mock CEF initialization failure unexpectedly succeeded' >&2
      exit 1
    fi
    assert_log 'initialize|'

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

    library="$out/lib/libsteam-cef-scale-override.so"
    readelf -h "$library" | grep -Fq 'Class:                             ELF64'
    readelf -d "$library" | grep -Fq '(SONAME)'
    readelf -Ws "$library" | grep -Eq 'GLOBAL +DEFAULT +[0-9]+ +cef_initialize$'
    if readelf -Ws "$library" | grep -Eq 'GLOBAL +DEFAULT +[0-9]+ +cef_execute_process$'; then
      echo 'unexpected cef_execute_process interposition' >&2
      exit 1
    fi

    runHook postInstallCheck
  '';

  meta = {
    description = "Process-scoped CEF scale override for Steam's desktop UI";
    homepage = "https://github.com/ianmh/nixpkgs-personal";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
