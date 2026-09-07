{
  lib,
  callPackage,
  fetchFromGitHub,
  jemalloc,
}:
let
  source = import ./source.nix;
  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia";
    inherit (source) rev hash;
  };
  upstream = callPackage ./upstream.nix {
    inherit src;
    inherit (source) version;
  };
in
upstream.overrideAttrs (old: {
  strictDeps = true;
  # Upstream lists the linked allocator among build tools. Strict dependency
  # separation requires its headers and pkg-config file in the target inputs.
  nativeBuildInputs = lib.remove jemalloc (old.nativeBuildInputs or [ ]);
  buildInputs = (old.buildInputs or [ ]) ++ [ jemalloc ];
  pname = "noctalia-personal";
  patches = (old.patches or [ ]) ++ [
    ./symbolic-bar-icons.patch
    ./media-player-selector.patch
  ];
  postPatch = (old.postPatch or "") + ''
    # Reject a stale version pin after source updates, without importing the source.
    grep -Fq "version: '${source.version}'" meson.build
    cp ${./bar_icon_policy.h} src/shell/bar/widgets/bar_icon_policy.h
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    $CXX -std=c++23 -Wall -Wextra -Werror -UNDEBUG -I../src \
      ${./test_bar_icon_policy.cpp} -o bar-icon-policy-test
    ./bar-icon-policy-test
    runHook postCheck
  '';
  postInstall = (old.postInstall or "") + ''
    install -Dm644 ${./README.md} "$out/share/doc/noctalia-personal/README.md"
  '';
  passthru = (old.passthru or { }) // {
    upstreamRevision = source.rev;
  };
  meta = old.meta // {
    description = "Noctalia with symbolic bar icons, exact tray icons, and landscape media playback cards";
  };
})
