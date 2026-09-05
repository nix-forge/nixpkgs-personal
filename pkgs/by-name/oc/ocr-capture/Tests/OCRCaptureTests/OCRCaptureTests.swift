import AppKit
import CoreGraphics
import XCTest

@testable import OCRCapture

final class ConfigurationParserTests: XCTestCase {
  func testCaptureDefaultsAreSimpleAndBounded() throws {
    let value = try ConfigurationParser.parse([])
    XCTAssertEqual(value.command, .capture)
    XCTAssertEqual(value.destinations, [.clipboard])
    XCTAssertEqual(value.maximumPixels, 24_000_000)
    XCTAssertEqual(value.recognitionBackend, .automatic)
  }

  func testImageCommandAndFeatureOptions() throws {
    let value = try ConfigurationParser.parse([
      "image", "/tmp/input.png", "--recognition", "adaptive", "--render", "table",
      "--language", "en-US", "--custom-word", "NixOS", "--destination", "stdout,file",
      "--output", "/tmp/result.tsv", "--json", "--small-text",
    ])
    XCTAssertEqual(value.command, .image("/tmp/input.png"))
    XCTAssertEqual(value.recognitionMode, .adaptive)
    XCTAssertEqual(value.renderMode, .table)
    XCTAssertEqual(value.languages, ["en-US"])
    XCTAssertEqual(value.customWords, ["NixOS"])
    XCTAssertEqual(value.destinations, [.stdout, .file])
    XCTAssertTrue(value.structuredJSON)
    XCTAssertTrue(value.smallText)
  }

  func testFileDestinationRequiresAPath() {
    XCTAssertThrowsError(try ConfigurationParser.parse(["capture", "--destination", "file"]))
  }

  func testDocumentBackendAndMarkdownAreParsed() throws {
    let value = try ConfigurationParser.parse([
      "capture", "--backend", "document", "--render", "markdown",
    ])
    XCTAssertEqual(value.recognitionBackend, .document)
    XCTAssertEqual(value.renderMode, .markdown)
  }

  func testNumericalBoundsAreValidated() {
    XCTAssertThrowsError(try ConfigurationParser.parse(["capture", "--max-pixels", "0"]))
    XCTAssertThrowsError(try ConfigurationParser.parse(["capture", "--minimum-text-height", "2"]))
    XCTAssertThrowsError(try ConfigurationParser.parse(["capture", "--candidates", "11"]))
  }

}

final class RendererTests: XCTestCase {
  func testRawPreservesObservationOrder() {
    let result = makeResult([
      observation("second", x: 0.1, y: 0.2),
      observation("first", x: 0.1, y: 0.8),
    ])
    XCTAssertEqual(OCRRenderer.render(result, as: .raw), "second\nfirst")
    XCTAssertEqual(OCRRenderer.render(result, as: .lines), "first\n\nsecond")
  }

  func testParagraphJoinsWrappedEnglishAndPreservesLists() {
    let result = makeResult([
      observation("A wrapped", x: 0.1, y: 0.84),
      observation("paragraph", x: 0.1, y: 0.78),
      observation("• first item", x: 0.1, y: 0.62),
      observation("continuation", x: 0.14, y: 0.56),
    ])
    XCTAssertEqual(
      OCRRenderer.render(result, as: .paragraph),
      "A wrapped paragraph\n\n• first item continuation"
    )
  }

  func testParagraphDoesNotInjectSpacesBetweenCJKLines() {
    let result = makeResult([
      observation("日本語", x: 0.1, y: 0.8),
      observation("文字列", x: 0.1, y: 0.74),
    ])
    XCTAssertEqual(OCRRenderer.render(result, as: .paragraph), "日本語文字列")
  }

  func testRightToLeftRowsUseReadingOrder() {
    let result = makeResult([
      observation("עולם", x: 0.35, y: 0.8, width: 0.2),
      observation("שלום", x: 0.7, y: 0.8, width: 0.2),
    ])
    XCTAssertEqual(OCRRenderer.render(result, as: .lines), "שלום עולם")
  }

  func testTableUsesStableColumnClusters() {
    let result = makeResult([
      observation("Name", x: 0.1, y: 0.8, width: 0.15),
      observation("Score", x: 0.65, y: 0.8, width: 0.15),
      observation("Ada", x: 0.1, y: 0.7, width: 0.15),
      observation("10", x: 0.65, y: 0.7, width: 0.15),
    ])
    XCTAssertEqual(OCRRenderer.render(result, as: .table), "Name\tScore\nAda\t10")
  }

  func testNativeTableTakesPrecedence() {
    var result = makeResult([observation("fallback", x: 0.1, y: 0.8)])
    result = OCRResult(
      observations: result.observations,
      sourceWidth: 100, sourceHeight: 100, scaleApplied: 1,
      elapsedSeconds: 0.1, nativeTableTSV: "native\tcell"
    )
    XCTAssertEqual(OCRRenderer.render(result, as: .table), "native\tcell")
  }

  func testCandidateConfidenceIsRetained() {
    let item = OCRObservation(
      candidates: [
        OCRCandidate(text: "primary", confidence: 0.5, rank: 0),
        OCRCandidate(text: "alternate", confidence: 0.4, rank: 1),
      ],
      boundingBox: NormalizedBox(CGRect(x: 0, y: 0, width: 1, height: 1))
    )
    XCTAssertEqual(item.candidates.count, 2)
    XCTAssertEqual(OCRRenderer.averageConfidence([item]), 0.5)
  }

  func testStructuredDocumentDrivesRawParagraphAndMarkdownRendering() {
    let title = OCRDocumentNode(
      kind: .title,
      transcript: "Quarterly Results",
      boundingBox: NormalizedBox(CGRect(x: 0.1, y: 0.9, width: 0.8, height: 0.05))
    )
    let paragraph = OCRDocumentNode(
      kind: .paragraph,
      transcript: "Revenue increased.",
      boundingBox: NormalizedBox(CGRect(x: 0.1, y: 0.75, width: 0.8, height: 0.08))
    )
    let list = OCRDocumentNode(
      kind: .list,
      boundingBox: NormalizedBox(CGRect(x: 0.1, y: 0.55, width: 0.8, height: 0.1)),
      children: [
        OCRDocumentNode(
          kind: .listItem,
          transcript: "Local-only OCR",
          attributes: ["markerType": "bullet"]
        )
      ]
    )
    let table = OCRDocumentNode(
      kind: .table,
      boundingBox: NormalizedBox(CGRect(x: 0.1, y: 0.25, width: 0.8, height: 0.2)),
      children: [
        OCRDocumentNode(
          kind: .tableRow,
          children: [
            OCRDocumentNode(kind: .tableCell, transcript: "Name"),
            OCRDocumentNode(kind: .tableCell, transcript: "Score"),
          ]),
        OCRDocumentNode(
          kind: .tableRow,
          children: [
            OCRDocumentNode(kind: .tableCell, transcript: "Ada"),
            OCRDocumentNode(kind: .tableCell, transcript: "10"),
          ]),
      ]
    )
    let documentNode = OCRDocumentNode(
      kind: .document,
      transcript: "Quarterly Results\nRevenue increased.",
      children: [title, paragraph, list, table]
    )
    let root = OCRDocumentNode(
      kind: .document,
      transcript: documentNode.transcript,
      children: [documentNode]
    )
    var result = makeResult([observation("fallback", x: 0.1, y: 0.8)])
    result.structuredDocument = OCRStructuredDocument(
      transcript: "Vision literal transcript",
      confidence: 0.95,
      root: root
    )

    XCTAssertEqual(OCRRenderer.render(result, as: .raw), "Vision literal transcript")
    XCTAssertEqual(OCRRenderer.render(result, as: .paragraph), "Revenue increased.")
    XCTAssertEqual(
      OCRRenderer.render(result, as: .markdown),
      "# Quarterly Results\n\nRevenue increased.\n\n- Local-only OCR\n\n| Name | Score |\n| --- | --- |\n| Ada | 10 |"
    )
  }

  private func observation(
    _ text: String, x: Double, y: Double, width: Double = 0.35, height: Double = 0.04
  ) -> OCRObservation {
    OCRObservation(
      candidates: [OCRCandidate(text: text, confidence: 0.9, rank: 0)],
      boundingBox: NormalizedBox(CGRect(x: x, y: y, width: width, height: height))
    )
  }

  private func makeResult(_ observations: [OCRObservation]) -> OCRResult {
    OCRResult(
      observations: observations, sourceWidth: 1_000, sourceHeight: 500,
      scaleApplied: 1, elapsedSeconds: 0.1, nativeTableTSV: nil
    )
  }
}

@MainActor
final class NativeUIRegressionTests: XCTestCase {
  func testInteractiveCaptureDelegatesToTheMacOSRegionSelector() {
    XCTAssertEqual(NativeRegionCapture.executableURL.path, "/usr/sbin/screencapture")
    XCTAssertEqual(NativeRegionCapture.arguments, ["-i", "-s", "-c", "-d"])
  }

  func testClipboardWriterVerifiesAndPublishesExactText() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("OCRCaptureTests.\(UUID())"))
    defer { pasteboard.releaseGlobally() }
    let writer = ClipboardWriter(pasteboard: pasteboard)
    let expected = "Exact Unicode: café 日本語\nsecond line"

    try writer.write(expected)

    XCTAssertEqual(pasteboard.string(forType: .string), expected)
  }
}

final class SecurityPolicyTests: XCTestCase {
  func testImageCommandReturnsFailureForMissingInput() throws {
    let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
      .appendingPathComponent("hm-ocr-capture")
    let process = Process()
    process.executableURL = executable
    process.arguments = ["image", "/tmp/ocr-capture-missing-\(UUID()).png"]
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationReason, .exit)
    XCTAssertEqual(process.terminationStatus, 1)
  }

  func testCaptureSessionLockRejectsConcurrentOwnership() throws {
    let first = try XCTUnwrap(CaptureSessionLock.acquire())
    XCTAssertNil(try CaptureSessionLock.acquire())
    withExtendedLifetime(first) {}
  }

  func testImagePreprocessorEnforcesPixelBudget() throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    #if compiler(>=6.2)
      // A nil data pointer asks CoreGraphics to allocate and own the bitmap.
      let optionalContext = unsafe CGContext(
        data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    #else
      let optionalContext = CGContext(
        data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    #endif
    let context = try XCTUnwrap(optionalContext)
    let image = try XCTUnwrap(context.makeImage())
    let prepared = try ImagePreprocessor.prepare(image, maximumPixels: 2_500, smallText: false)
    XCTAssertEqual(prepared.image.width, 50)
    XCTAssertEqual(prepared.image.height, 50)
    XCTAssertEqual(prepared.scaleApplied, 0.5, accuracy: 0.001)
  }

  func testImagePreprocessorResizesCMYKInput() throws {
    let data = Data(repeating: 0, count: 100 * 100 * 4)
    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    #if compiler(>=6.2)
      // The provider owns the pixel bytes; no custom decode pointer is supplied.
      let optionalImage = unsafe CGImage(
        width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 400,
        space: CGColorSpaceCreateDeviceCMYK(), bitmapInfo: CGBitmapInfo(), provider: provider,
        decode: nil, shouldInterpolate: true, intent: .defaultIntent
      )
    #else
      let optionalImage = CGImage(
        width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 400,
        space: CGColorSpaceCreateDeviceCMYK(), bitmapInfo: CGBitmapInfo(), provider: provider,
        decode: nil, shouldInterpolate: true, intent: .defaultIntent
      )
    #endif
    let image = try XCTUnwrap(optionalImage)
    let prepared = try ImagePreprocessor.prepare(image, maximumPixels: 2_500, smallText: false)
    XCTAssertEqual(prepared.image.width, 50)
    XCTAssertEqual(prepared.image.height, 50)
    XCTAssertEqual(prepared.image.colorSpace?.model, .rgb)
  }
}
