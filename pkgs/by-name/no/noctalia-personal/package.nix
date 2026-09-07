{ callPackage, fetchFromGitHub }:
let
  source = import ./source.nix;
  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia";
    inherit (source) rev hash;
  };
  upstream = callPackage "${src}/nix/package.nix" { };
in
assert upstream.version == source.version;
upstream.overrideAttrs (old: {
  pname = "noctalia-personal";
  patches = (old.patches or [ ]) ++ [
    ./symbolic-bar-icons.patch
    ./media-player-selector.patch
  ];
  postPatch = (old.postPatch or "") + ''
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
