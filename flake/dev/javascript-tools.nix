{ pkgs }:
let
  # Declaration archives are fixed Nix inputs, unpacked without npm or lifecycle scripts.
  typings =
    pkgs.runCommand "repository-typescript-declarations"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
        node = pkgs.fetchurl {
          url = "https://registry.npmjs.org/@types/node/-/node-24.13.6.tgz";
          hash = "sha512-SGrw/h3KPFshy3OE6ZL53LMBG5vGQQ8/gIpiqz/kRZhPJ7HgwCEs8LBuNtWLa8dvGZVpSF7+Bf+c11HUrCb/yg==";
        };
        undiciArchive = pkgs.fetchurl {
          url = "https://registry.npmjs.org/undici-types/-/undici-types-7.18.2.tgz";
          hash = "sha512-AsuCzffGHJybSaRrmr5eHr81mwJU3kjw6M+uprWvCXiNeN9SOGwQ3Jn8jb8m3Z6izVgknn1R0FTCEAP2QrLY/w==";
        };
      }
      ''
        mkdir -p "$out/node" "$out/undici-types"
        tar -xzf "$node" --strip-components=1 -C "$out/node"
        tar -xzf "$undiciArchive" --strip-components=1 -C "$out/undici-types"
      '';
  compiler = pkgs.writeShellScriptBin "tsc" ''
    exec ${pkgs.lib.getExe' pkgs.typescript "tsc"} --typeRoots ${typings} "$@"
  '';
  check = pkgs.writeShellApplication {
    name = "javascript-check";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      compiler
      pkgs.nodejs-slim_24
      pkgs.oxlint
      pkgs.prettier
    ];
    text = (import ../../lib/render-text.nix) ./scripts/javascript-lint.sh.in { inherit typings; };
  };
in
pkgs.symlinkJoin {
  name = "repository-javascript-tools";
  paths = [
    compiler
    check
    pkgs.nodejs-slim_24
    pkgs.oxlint
    pkgs.prettier
  ];
  meta.mainProgram = "javascript-check";
}
