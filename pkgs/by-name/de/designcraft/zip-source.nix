# Pin the patched ZIP source independently of the Cargo vendor lock.
{
  applyPatches,
  fetchurl,
  patches,
}:
applyPatches {
  name = "zip-9.5.0-craft-source";
  src = fetchurl {
    name = "zip-9.5.0.tar.gz";
    url = "https://static.crates.io/crates/zip/zip-9.5.0.crate";
    hash = "sha256-BwDmxCev9krNvwLoX7/ZRsLuEjGdGvATCS86IXiRT/g=";
  };
  inherit patches;
}
