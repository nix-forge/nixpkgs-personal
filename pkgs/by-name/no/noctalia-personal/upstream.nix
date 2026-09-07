# Adapted from noctalia nix/package.nix at the revision in source.nix.
# See UPSTREAM-LICENSE for the MIT license.
# Only source/version injection differs; review this file when updating upstream.
{
  src,
  version,
  lib,
  config,
  stdenv,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  libGL,
  libglvnd,
  freetype,
  fontconfig,
  cairo,
  pango,
  harfbuzz,
  libxkbcommon,
  sdbus-cpp_2,
  systemd,
  pipewire,
  pam,
  curl,
  libwebp,
  libjxl,
  libsndfile,
  glib,
  polkit,
  librsvg,
  libqalculate,
  libxml2,
  md4c,
  libsecret,
  libsodium,
  stb,
  fetchFromGitHub,
  nlohmann_json,
  tomlplusplus,
  libical,
  wireplumber,
  jemalloc,
  makeWrapper,
  git,
  autoAddDriverRunpath,
  # DEPRECATED: no longer affects the build; kept for `.override` compat.
  cudaSupport ? config.cudaSupport,
}:
let
  stb' = stb.overrideAttrs (_: {
    version = "unstable-2025-10-26";
    src = fetchFromGitHub {
      owner = "nothings";
      repo = "stb";
      rev = "f1c79c02822848a9bed4315b12c8c8f3761e1296";
      hash = "sha256-BlyXJtAI7WqXCTT3ylww8zoG0hBxaojJnQDvdQOXJPE=";
    };
  });
in
lib.warnIf cudaSupport
  "noctalia: `cudaSupport` no longer has any effect (autoAddDriverRunpath is now always applied); this argument will be removed in the future."
  stdenv.mkDerivation
  {
    pname = "noctalia";
    inherit version;

    inherit src;

    postFixup = ''
      wrapProgram $out/bin/noctalia \
        --prefix PATH : ${lib.makeBinPath [ git ]}

      $out/bin/noctalia completions bash | install -D /dev/stdin $out/share/bash-completion/completions/noctalia
      $out/bin/noctalia completions zsh  | install -D /dev/stdin $out/share/zsh/site-functions/_noctalia
      $out/bin/noctalia completions fish | install -D /dev/stdin $out/share/fish/vendor_completions.d/noctalia.fish
    '';

    nativeBuildInputs = [
      meson
      ninja
      pkg-config
      wayland-scanner
      jemalloc
      makeWrapper
      autoAddDriverRunpath
    ];

    buildInputs = [
      wayland
      wayland-protocols
      libGL
      libglvnd
      freetype
      fontconfig
      cairo
      pango
      harfbuzz
      libxkbcommon
      sdbus-cpp_2
      systemd
      pipewire
      wireplumber
      pam
      curl
      libwebp
      libjxl
      libsndfile
      glib
      polkit
      librsvg
      libqalculate
      libxml2
      md4c
      libsecret
      libsodium
      stb'
      nlohmann_json
      tomlplusplus
      libical
    ];

    mesonBuildType = "release";

    ninjaFlags = [ "-v" ];

    meta = with lib; {
      description = "A sleek, customizable desktop shell crafted for Wayland.";
      homepage = "https://github.com/noctalia-dev/noctalia";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "noctalia";
    };
  }
