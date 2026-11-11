let
  flake = builtins.getFlake ("git+file://" + toString ../..);
  tools = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
in
{
  package = flake.packages.${builtins.currentSystem}.scrypted-server;
  node = tools.nodejs_24;
  candidate = tools.runCommand "forge-1.4.3-candidate" {
    src = tools.fetchurl {
      url = "https://registry.npmjs.org/node-forge/-/node-forge-1.4.3.tgz";
      hash = "sha512-P6wzfh6t70avmV8FrVEAd/36sOPJQ+hkaJVX1Laap9J/77m7M0eyozDvc8SwnDf4P7MP94gwbAAo0rg3YVXT+g==";
    };
    nativeBuildInputs = [ tools.gnutar tools.gzip ];
  } ''
    mkdir -p "$out"
    tar -xzf "$src" -C "$out" --strip-components=1
  '';
}
