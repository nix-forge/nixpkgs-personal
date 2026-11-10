{ npmDepsHash ? "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" }:
let
  flake = builtins.getFlake ("git+file://" + toString ../..);
  tools = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  package = flake.packages.${builtins.currentSystem}.scrypted-server.overrideAttrs {
    inherit npmDepsHash;
  };
in
{
  inherit package;
  npmDeps = package.npmDeps;
  node = tools.nodejs_24;
  baseline = tools.runCommand "forge-1.4.1-baseline" {
    src = tools.fetchurl {
      url = "https://registry.npmjs.org/node-forge/-/node-forge-1.4.1.tgz";
      hash = "sha512-w5/MfWaeMrpR/5ba6fZyAUTLSuE6aYz7H/3cYrqwZEmf5eQS3IaaLgJt4MBv7HglGFWmV22K8h4U18RJQmw/ow==";
    };
    nativeBuildInputs = [ tools.gnutar tools.gzip ];
  } ''
    mkdir -p "$out"
    tar -xzf "$src" -C "$out" --strip-components=1
  '';
}
