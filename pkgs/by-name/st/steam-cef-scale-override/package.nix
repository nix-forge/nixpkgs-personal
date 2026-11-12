{
  lib,
  fetchFromGitHub,
  meson,
  ninja,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "steam-cef-scale-override";
  version = "1.0.1";

  src = fetchFromGitHub {
    owner = "IanHollow";
    repo = "steam-cef-scale-override";
    rev = "fa2509a0e69249a9b249d3eacbcca4c1532f9ded";
    hash = "sha256-U0h0R2DuzLCl8H9loMk1Y9Lf7vBzP7tmpWnB7yo2bMo=";
  };
  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
  ];
  # Meson's release build type implies -O3. Keep the package's reviewed -O2
  # policy while expressing the remaining release settings as built-in options.
  mesonBuildType = "custom";
  mesonFlags = [
    "-Db_ndebug=true"
    "-Doptimization=2"
    "-Dtests=true"
  ];

  doCheck = true;
  postCheck = builtins.readFile ./scripts/post-check.sh;

  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Process-scoped CEF scale override for Steam's desktop UI";
    homepage = "https://github.com/IanHollow/steam-cef-scale-override";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
