{
  lib,
  stdenv,
  runCommand,
  appstream,
  package,
}:
lib.optionalAttrs stdenv.hostPlatform.isLinux {
  appstream = runCommand "${package.pname}-appstream" { nativeBuildInputs = [ appstream ]; } ''
    for metadata in ${package}/share/metainfo/*.xml; do
      appstreamcli validate --no-net "$metadata"
    done
    touch "$out"
  '';
}
