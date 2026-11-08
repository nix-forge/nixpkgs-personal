{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  nodejs,
}:
let
  source = (import ./source.nix).pnpm;
  platform = source.sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "aurral-pnpm";
  inherit (source) version;
  strictDeps = true;
  src = fetchurl {
    url = "https://registry.npmjs.org/@pnpm/exe.linux-${platform.arch}/-/exe.linux-${platform.arch}-${source.version}.tgz";
    inherit (platform) hash;
  };
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  propagatedBuildInputs = [ nodejs ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 pnpm "$out/bin/pnpm"
    install -Dm644 LICENSE "$out/share/licenses/pnpm/LICENSE"
    runHook postInstall
  '';
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/pnpm-home"
    mkdir -p "$HOME"
    cd "$TMPDIR"
    test "$("$out/bin/pnpm" --version)" = ${lib.escapeShellArg source.version}
    test "$(pnpm_config_store_index_format=files "$out/bin/pnpm" config get storeIndexFormat)" = files
    case "$(patchelf --print-interpreter "$out/bin/pnpm")" in
      /nix/store/*) ;;
      *) echo "pnpm retained a non-store ELF interpreter" >&2; exit 1 ;;
    esac
    runHook postInstallCheck
  '';
  passthru.nodejs-slim = nodejs;
  meta = {
    license = lib.licenses.mit;
    platforms = builtins.attrNames source.sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
