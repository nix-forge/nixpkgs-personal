# Keep the repaired transitive ZIP dependency explicit and hash-pinned.
{
  applyPatches,
  fetchurl,
  patches,
  postPatch ? "",
}:
applyPatches {
  name = "candle-core-0.9.2-craft-source";
  src = fetchurl {
    name = "candle-core-0.9.2.tar.gz";
    url = "https://static.crates.io/crates/candle-core/candle-core-0.9.2.crate";
    hash = "sha256-wVtnW4DZlLLq2yCku+Q06r60VOrD7l4rTPbxR+6b4JE=";
  };
  inherit patches postPatch;
}
