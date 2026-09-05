# OCR Capture

OCR Capture is a small, native macOS screenshot-to-text helper packaged for
`nixpkgs-personal`.

Press `Command-Shift-7`, select a region with the standard macOS Screenshot
interaction, and the recognized text replaces the captured image on the normal
system clipboard. macOS owns the complete interaction: cursor, coordinate
display, selection behavior, multi-display handling, Escape cancellation,
permission UI, and capture sound. OCR Capture does not draw an overlay, reticle,
progress HUD, notification, or review window.

## Implementation

The Swift app runs macOS's built-in `/usr/sbin/screencapture` in interactive
region and clipboard mode, decodes the resulting in-memory pasteboard image,
recognizes its text locally with Vision, and writes plain text back to the
pasteboard. It does not create an intermediate screenshot file, contact a
network service, or keep a resident process after the result is copied.

The normal capture is intentionally one action:

```console
hm-ocr-capture capture --recognition accurate --backend automatic --render lines
```

Image and standard-input commands remain available for testing and automation:

```console
hm-ocr-capture image scan.png --backend document --render markdown --destination stdout
cat scan.png | hm-ocr-capture stdin --json
hm-ocr-capture languages
hm-ocr-capture diagnose
```

Run `hm-ocr-capture help` for OCR and rendering options.

## Privacy and security

- Capture and OCR remain local to the Mac.
- Screenshots pass through the standard clipboard and are not written to disk.
- OCR scans text only; QR actions, speech, history, review UI, custom feedback,
  and clipboard expiry have been removed.
- The final text uses the normal persistent macOS clipboard, including the
  system's standard Universal Clipboard behavior.
- Input bytes, recognition pixels, candidate counts, and OCR duration remain
  bounded.

## Compatibility

The app has a macOS 14 deployment target. Its legacy backend uses
`VNRecognizeTextRequest`. When the build compiler and Apple SDK expose the newer
structured document-recognition API, the automatic backend enables it at build
time while retaining the legacy fallback for older systems.

Nix probes the actual Vision module because nixpkgs can ship a newer Swift
compiler before a newer Apple SDK. Swift 5 builds compile the available adapter;
Swift 6 builds use strict concurrency and automatically include newer Vision
features when the SDK provides them.

## Development checks

From the `nixpkgs-personal` development shell:

```console
nix develop
pkgs/by-name/oc/ocr-capture/Scripts/check-quality.sh
```

The suite runs swift-format, SwiftLint, compiler warnings and strict concurrency,
unit tests, strict-memory checks, Periphery, AddressSanitizer, and
ThreadSanitizer. The Nix package repeats its hermetic self-test, signature,
deployment-target, and dependency checks.
