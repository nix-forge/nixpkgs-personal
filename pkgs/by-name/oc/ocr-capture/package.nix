{
  replaceVars,
  coreutils,
  file,
  findutils,
  gnugrep,
  lib,
  fetchFromGitHub,
  rcodesign,
  re-plistbuddy,
  stdenv,
  python3,
  swift,
  writeText,
}:

let
  version = "0.1.0";
  minimumMacOS = "14.0";
  swiftLanguageVersion = if lib.versionAtLeast swift.version "6" then "6" else "5";
  infoPlist = writeText "OCRCapture-Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleDevelopmentRegion = "en";
      CFBundleDisplayName = "OCR Capture";
      CFBundleExecutable = "hm-ocr-capture";
      CFBundleIdentifier = "dev.ianmh.OCRCapture";
      CFBundleInfoDictionaryVersion = "6.0";
      CFBundleName = "OCR Capture";
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = version;
      CFBundleSupportedPlatforms = [ "MacOSX" ];
      CFBundleVersion = version;
      LSApplicationCategoryType = "public.app-category.productivity";
      LSMinimumSystemVersion = minimumMacOS;
      LSMultipleInstancesProhibited = true;
      LSUIElement = true;
      NSHighResolutionCapable = true;
      NSScreenCaptureUsageDescription = "OCR Capture reads only the screen area you select and recognizes its text locally.";
      NSHumanReadableCopyright = "Copyright © 2026 Ian Holloway";
    }
  );
in
stdenv.mkDerivation {
  pname = "ocr-capture";
  inherit version;

  src = fetchFromGitHub {
    owner = "IanHollow";
    repo = "ocr-capture";
    rev = "2557e8fd4bfc2865cb5ca68d99b73d8518fb881e";
    hash = "sha256-O733558BPDHg5lK76vhaUsWIOfLYQRmTyWvw1HTwXEE=";
  };
  nativeBuildInputs = [
    coreutils
    file
    findutils
    gnugrep
    rcodesign
    re-plistbuddy
    swift
  ];
  strictDeps = true;
  MACOSX_DEPLOYMENT_TARGET = minimumMacOS;
  # Swift's explicit deployment target matches the target verified below.
  # cc-wrapper's generic multi-target warning does not account for this case.
  NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = 1;

  dontConfigure = true;

  buildPhase = ''
    source ${
      replaceVars ./scripts/build-phase.sh {
        stdenv_hostPlatform_darwinArch = stdenv.hostPlatform.darwinArch;
        inherit minimumMacOS;
        inherit swiftLanguageVersion;
      }
    }
  '';

  doCheck = true;
  checkPhase = builtins.readFile ./scripts/check-phase.sh;

  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit infoPlist; }}
  '';

  postFixup = ''
    source ${
      replaceVars ./scripts/post-fixup.sh {
        rcodesign = lib.getExe rcodesign;
      }
    }
  '';

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/OCR Capture.app" --expected-version ${lib.escapeShellArg version} --authored
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit minimumMacOS;
        rcodesign = lib.getExe rcodesign;
      }
    }
  '';

  meta = {
    description = "Native macOS region-screenshot OCR tool";
    homepage = "https://github.com/IanHollow/ocr-capture";
    license = lib.licenses.mit;
    mainProgram = "hm-ocr-capture";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "OCR Capture.app"; };

  passthru = {
    inherit swiftLanguageVersion;
    swiftVersion = swift.version;
    documentRecognition = "compile-probed";
  };
}
