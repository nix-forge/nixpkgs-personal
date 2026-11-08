{
  version = "0.8.0";
  releaseDate = "2026-10-14";
  releaseType = "stable";
  upstreamVersion = "0.8.0";
  rev = "9931329b9fae0b05373b4dc3ac7c58541f0891a4";
  hash = "sha256-gPd3NSEaeBEP5m0zUHI92vrqPd0pQSItuF44ZHaTnco=";
  fonts = {
    rev = "3d9ab3a132ed0eff457e424226a435a901da30d3";
    hash = "sha256-mNnDzBcOp1X10dzmiW0iBAkb74QjuzMO4slWudxXCTE=";
  };
  droid = {
    font = {
      url = "https://raw.githubusercontent.com/watli01/craft-fonts/1e39ddaf4c468a059c69ce11b5e5849fd54a39fa/fonts/droid-sans-fallback/DroidSansFallbackFull.ttf";
      hash = "sha256-I5IBVTBDi6/Ejt/ErubZ3iOH9iemE02Ks9/MmdIcgkA=";
    };
    notice = {
      url = "https://raw.githubusercontent.com/watli01/craft-fonts/1e39ddaf4c468a059c69ce11b5e5849fd54a39fa/fonts/droid-sans-fallback/NOTICE";
      hash = "sha256-OHUSRTieHiP3Pm9ThLXL5/qXLMRBDFrcnASwgqC5Vho=";
    };
  };
  thai = {
    font = {
      url = "https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notosansthai/NotoSansThai%5Bwdth%2Cwght%5D.ttf";
      hash = "sha256-WhxVm7U5WDyKH9mdHFuUkeXhRHjJzSvQlw1cMJbMnvg=";
    };
    notice = {
      url = "https://raw.githubusercontent.com/google/fonts/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notosansthai/OFL.txt";
      hash = "sha256-Lpj9I6UtJT24YSzVlCyPL/QRGyHSNnBQ/cqR2MzDdKA=";
    };
  };
  ocr = {
    detection = {
      url = "https://ocrs-models.s3-accelerate.amazonaws.com/text-detection.rten";
      hash = "sha256-8Vz7Vr0CxL9HiiA0OYZQSh8B4WZcKzoK1mNA8FSxtco=";
    };
    recognition = {
      url = "https://ocrs-models.s3-accelerate.amazonaws.com/text-recognition.rten";
      hash = "sha256-5ISGbUzOQDF1vY0AsSj+sIq0LiCN4w5CzZiJ2PFzWm4=";
    };
    license = {
      url = "https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt";
      hash = "sha256-KKlSnH0LtNxR9L9cEWo9Fu8kegUvdZFGZ2jd9WP9HPU=";
    };
  };
  gitDependencies = {
    "craft-print-0.1.0" = {
      url = "https://github.com/storytold/craft-libs";
      rev = "f03ec27ab2c405969428512178f746183cd55ca0";
      hash = "sha256-QtSjPVQSYsqqmg/9mtfC4ueAFcZ3IcL4gb29B+BfgmY=";
    };
    "craft-ui-0.1.0" = {
      url = "https://github.com/storytold/craft-libs";
      rev = "5c874d51eeb3de70e735c8ce87a59a7dedd47675";
      hash = "sha256-VhLeT7VLdZAIz6gR9PdFI34IJxHsGF8NE0uzFCN2vIU=";
    };
    "winprint-0.2.1" = {
      url = "https://github.com/storytold/winprint.rs";
      rev = "5f80b9baf6b58937c401656634e42d33f00ddf49";
      hash = "sha256-wnz/VbqQ3j/x1PEq6Elxu/oSjVqdONfqQmZ31NsTIIc=";
    };
  };
}
