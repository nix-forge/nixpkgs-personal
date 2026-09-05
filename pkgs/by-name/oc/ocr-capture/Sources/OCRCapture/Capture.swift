import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Delegates the complete interaction to the same macOS Screenshot service used
/// by Shift-Command-4. OCR Capture never draws a selection surface of its own.
@MainActor
final class NativeRegionCapture {
  static let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  static let arguments = ["-i", "-s", "-c", "-d"]

  private let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func capture() throws -> CGImage {
    let originalChangeCount = pasteboard.changeCount
    let process = Process()
    process.executableURL = Self.executableURL
    process.arguments = Self.arguments

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw OCRCaptureError.captureUnavailable(error.localizedDescription)
    }

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw OCRCaptureError.captureFailed(
        "macOS Screenshot exited with status \(process.terminationStatus)"
      )
    }
    // screencapture exits successfully when Escape cancels. A completed capture
    // always advances the pasteboard generation, even if its pixels are equal.
    guard pasteboard.changeCount != originalChangeCount else {
      throw OCRCaptureError.selectionCancelled
    }

    guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw OCRCaptureError.captureFailed(
        "macOS Screenshot did not place a readable image on the clipboard"
      )
    }
    return image
  }
}
