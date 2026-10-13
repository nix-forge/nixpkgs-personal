{
  checkout ? ../..,
}:
let
  flake = builtins.getFlake (toString checkout);
  pkgs = flake.legacyPackages.aarch64-darwin;
  source = import ../../pkgs/by-name/vo/vorssaint/source.nix;
  recipe = flake.packages.aarch64-darwin.vorssaint;
in
assert pkgs.swift.version == "6.2.4";
assert pkgs.sqlite.version == "3.53.3";
assert source.version == "3.4.0";
assert source.src.hash == "sha256-2D74XjE6XHj65hCiTuAag/0VPU3bo2lB5N8RnBmLCgY=";
assert source.src.rev == "c9cfa0d1014c885119bf35bbac850d670267a723";
recipe.overrideAttrs (_old: {
  pname = "vorssaint-compiler-diagnostic";
  # Preserve the original locked source, stdenv/SDK, dependencies, zero-fuzz
  # package patches and trusted rebranding; run no upstream build helpers.
  buildPhase = ''
    export DIAGNOSTIC_SQLITE_HEADER=${pkgs.lib.getDev pkgs.sqlite}/include/sqlite3.h
    export DIAGNOSTIC_SQLITE_LIBRARY=${pkgs.lib.getLib pkgs.sqlite}/lib
    export DIAGNOSTIC_SQLITE_SMOKE=${../../pkgs/by-name/vo/vorssaint/check_sqlite.swift}
    export DIAGNOSTIC_REPORT="$out"
    mkdir -p "$out"
    cp ${
      pkgs.writeText "diagnostic-provenance.json" (
        builtins.toJSON {
          inherit (source) version src;
          swift = pkgs.swift.version;
          sqlite = pkgs.sqlite.version;
          diagnosticOnly = true;
        }
      )
    } "$out/provenance.json"
    python3 ${./vors-compiler.py}
  '';
  installPhase = "true";
  doCheck = false;
  doInstallCheck = false;
  dontFixup = true;
})
