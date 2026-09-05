import CoreGraphics
import Foundation

enum OCRCaptureSelfTest {
  static func run() throws {
    let defaults = try ConfigurationParser.parse([])
    try require(defaults.destinations == [.clipboard], "capture must default to the clipboard")
    try require(defaults.maximumPixels == 24_000_000, "pixel budget changed unexpectedly")

    let top = observation("first", x: 0.1, y: 0.8)
    let bottom = observation("second", x: 0.1, y: 0.2)
    let result = OCRResult(
      observations: [bottom, top], sourceWidth: 100, sourceHeight: 100,
      scaleApplied: 1, elapsedSeconds: 0, nativeTableTSV: nil
    )
    try require(
      OCRRenderer.render(result, as: .raw) == "second\nfirst", "raw renderer reordered observations"
    )
    try require(
      OCRRenderer.render(result, as: .lines) == "first\n\nsecond", "line renderer ordering failed")

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    #if compiler(>=6.2)
      // A nil data pointer asks CoreGraphics to allocate and own the bitmap.
      let context = unsafe CGContext(
        data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    #else
      let context = CGContext(
        data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    #endif
    guard
      let context, let image = context.makeImage()
    else { throw OCRCaptureError.captureFailed("self-test image allocation failed") }
    let prepared = try ImagePreprocessor.prepare(image, maximumPixels: 2_500, smallText: false)
    try require(
      prepared.image.width == 50 && prepared.image.height == 50, "pixel budget scaling failed")
  }

  private static func observation(_ text: String, x: Double, y: Double) -> OCRObservation {
    OCRObservation(
      candidates: [OCRCandidate(text: text, confidence: 0.9, rank: 0)],
      boundingBox: NormalizedBox(CGRect(x: x, y: y, width: 0.3, height: 0.04))
    )
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw OCRCaptureError.recognitionFailed("self-test: \(message)") }
  }
}
