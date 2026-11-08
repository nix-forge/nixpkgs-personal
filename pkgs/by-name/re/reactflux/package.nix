{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  nodejs_24,
  typescript,
  oxlint,
  defaultServerUrl ? null,
  readerDefaults ? { },
}:
let
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "reactflux";
  inherit (source) version;
  src = fetchFromGitHub {
    owner = "electh";
    repo = "ReactFlux";
    inherit (source) rev hash;
  };
  strictDeps = true;
  nativeBuildInputs = [
    nodejs_24
    typescript
    oxlint
    pnpm_11
    pnpmConfigHook
  ];
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = source.pnpmHash;
  };
  patches = [
    ./deployment.patch
    ./typescript-parser.patch
  ];
  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        browser_auth_mts = "${./browser-auth.mts}";
        articleImageGallery_tsx = "${./ArticleImageGallery.tsx}";
        media_policy_mts = "${./media-policy.mts}";
        authState_mts = "${./authState.mts}";
        defaultSettings = lib.escapeShellArg "const DEFAULT_SETTINGS = { ...UPSTREAM_SETTINGS, ...${builtins.toJSON readerDefaults} }; export const createDefaultSettings";
      }
    }
  '';
  env = {
    VITE_BASE_PATH = "/";
    VITE_MINIFLUX_URL = if defaultServerUrl == null then "" else defaultServerUrl;
    SOURCE_COMMIT = source.rev;
    SOURCE_COMMIT_DATE = "2026-10-11T02:58:23Z";
  };
  buildPhase = builtins.readFile ./scripts/build-phase.sh;
  doCheck = true;
  checkPhase = ''
    source ${
      replaceVars ./scripts/check-phase.sh {
        auth_test_mts = "${./auth.test.mts}";
        images_test_mts = "${./images.test.mts}";
        typescript_config = "${./application-types.json}";
        lint_config = "${./.oxlintrc.json}";
      }
    }
  '';
  installPhase = builtins.readFile ./scripts/install-phase.sh;
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;
  meta = {
    description = "Image-based RSS reader interface for Miniflux";
    homepage = "https://github.com/electh/ReactFlux";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
