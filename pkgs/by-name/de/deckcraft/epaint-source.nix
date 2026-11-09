# Keep the corrected renderer and its complete notices pinned independently of Cargo.
{ applyPatches, fetchurl }:
let
  upstream = "https://raw.githubusercontent.com/emilk/egui/49682f8baa058bf49e011035cfbd6e825f88a5ef";
  mit = fetchurl {
    url = "${upstream}/LICENSE-MIT";
    hash = "sha256-lcqS9fjqUjHxWAs6KnmegmCvMRS5AOHe9TVaf0S89gw=";
  };
  apache = fetchurl {
    url = "${upstream}/LICENSE-APACHE";
    hash = "sha256-gXPVwptPlW1TJ4HSuG5OMPg+a3h43OGMkZRR1rpwfJA=";
  };
in
applyPatches {
  name = "epaint-0.36.2-deckcraft-source";
  src = fetchurl {
    name = "epaint-0.36.2.tar.gz";
    url = "https://static.crates.io/crates/epaint/epaint-0.36.2.crate";
    hash = "sha256-oOwDCNwjEw/Bp9RiOoU0wu0GnG3ITiWO5PPemWFaoaM=";
  };
  patches = [ ./epaint-glyph-presence.patch ];
  # The crate archive omits repository-root licences; preserve them from its VCS revision.
  postPatch = ''
    cp ${mit} LICENSE-MIT
    cp ${apache} LICENSE-APACHE
  '';
}
