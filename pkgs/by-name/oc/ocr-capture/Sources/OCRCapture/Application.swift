import AppKit
import CoreGraphics
import Foundation

@MainActor
final class OCRCaptureApplication: NSObject, NSApplicationDelegate {
  private let configuration: OCRConfiguration
  private let capture = NativeRegionCapture()
  private let recognition = OCRService()
  private let clipboard = ClipboardWriter()
  private var activeTask: Task<Void, Never>?

  init(configuration: OCRConfiguration) {
    self.configuration = configuration
    super.init()
  }

  func applicationDidFinishLaunching(_: Notification) {
    activeTask = Task { [weak self] in await self?.run() }
  }

  func applicationWillTerminate(_: Notification) {
    activeTask?.cancel()
    recognition.cancel()
  }

  private func run() async {
    do {
      switch configuration.command {
      case .help:
        writeStandardOutput(usage + "\n")
        terminate()
      case .languages:
        let languages = try recognition.supportedLanguages(
          for: configuration.recognitionMode,
          backend: configuration.recognitionBackend
        )
        writeStandardOutput(languages.joined(separator: "\n") + "\n")
        terminate()
      case .diagnose:
        try diagnose()
        terminate()
      case .selftest:
        try OCRCaptureSelfTest.run()
        writeStandardOutput("OCR Capture self-test passed.\n")
        terminate()
      case .image(let path):
        let image = try ImageLoader.fromFile(path, maximumBytes: configuration.maximumInputBytes)
        try await recognizeAndDeliver([image], interactive: false)
      case .stdin:
        let image = try ImageLoader.fromStandardInput(maximumBytes: configuration.maximumInputBytes)
        try await recognizeAndDeliver([image], interactive: false)
      case .capture:
        let image = try capture.capture()
        try await recognizeAndDeliver([image], interactive: true)
      }
    } catch is CancellationError {
      terminate()
    } catch let error as OCRCaptureError where error.isCancellation {
      terminate()
    } catch {
      present(error)
    }
  }

  private func recognizeAndDeliver(_ images: [CGImage], interactive: Bool) async throws {
    var results: [OCRResult] = []
    for image in images {
      try Task.checkCancellation()
      results.append(try await recognition.recognize(image, configuration: configuration))
    }
    let result = merge(results)
    guard !result.observations.isEmpty else { throw OCRCaptureError.noText }
    let rendered = OCRRenderer.render(result, as: configuration.renderMode)
    guard !rendered.isEmpty else { throw OCRCaptureError.noText }
    let payload = try outputPayload(result: result, rendered: rendered)
    try deliver(payload: payload, rendered: rendered)
    if !result.warnings.isEmpty, !interactive {
      writeStandardError(result.warnings.joined(separator: "\n") + "\n")
    }
    terminate()
  }

  private func merge(_ results: [OCRResult]) -> OCRResult {
    guard let first = results.first else {
      return OCRResult(
        observations: [], sourceWidth: 0, sourceHeight: 0, scaleApplied: 1,
        elapsedSeconds: 0, nativeTableTSV: nil)
    }
    let structured = results.compactMap(\.structuredDocument)
    let mergedDocument: OCRStructuredDocument?
    if structured.isEmpty {
      mergedDocument = nil
    } else {
      let transcript = structured.map(\.transcript).filter { !$0.isEmpty }.joined(separator: "\n\n")
      let confidence = structured.map(\.confidence).reduce(0, +) / Float(structured.count)
      mergedDocument = OCRStructuredDocument(
        transcript: transcript,
        confidence: confidence,
        root: OCRDocumentNode(
          kind: .document,
          transcript: transcript,
          confidence: confidence,
          attributes: ["documentCount": String(structured.count)],
          children: structured.flatMap(\.root.children)
        )
      )
    }
    let backends = Set(results.map(\.backend))
    return OCRResult(
      observations: results.flatMap(\.observations),
      sourceWidth: first.sourceWidth,
      sourceHeight: first.sourceHeight,
      scaleApplied: results.map(\.scaleApplied).min() ?? 1,
      elapsedSeconds: results.map(\.elapsedSeconds).reduce(0, +),
      nativeTableTSV: results.compactMap(\.nativeTableTSV).joined(separator: "\n\n").nilIfEmpty,
      backend: backends.count == 1 ? first.backend : .mixed,
      structuredDocument: mergedDocument,
      warnings: results.flatMap(\.warnings)
    )
  }

  private func outputPayload(result: OCRResult, rendered: String) throws -> String {
    guard configuration.structuredJSON else { return rendered }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try decodeUTF8(encoder.encode(result))
  }

  private func deliver(payload: String, rendered: String) throws {
    if configuration.destinations.contains(.clipboard) {
      try clipboard.write(rendered)
    }
    if configuration.destinations.contains(.stdout) {
      writeStandardOutput(payload + (payload.hasSuffix("\n") ? "" : "\n"))
    }
    if configuration.destinations.contains(.file), let path = configuration.outputPath {
      try FileOutput.write(payload, to: path, append: configuration.appendOutput)
    }
  }

  private func diagnose() throws {
    let accurate = try recognition.supportedLanguages(for: .accurate, backend: .legacy)
    let fast = try recognition.supportedLanguages(for: .fast, backend: .legacy)
    let report: [String: Any] = [
      "bundleIdentifier": Bundle.main.bundleIdentifier ?? OCRCaptureEntry.bundleIdentifier,
      "screenCapturePermission": CGPreflightScreenCaptureAccess(),
      "documentRecognitionCompiled": DocumentRecognitionCapability.isCompiled,
      "documentRecognitionAvailable": DocumentRecognitionCapability.isAvailable,
      "requestedBackend": configuration.recognitionBackend.rawValue,
      "accurateLanguageCount": accurate.count,
      "fastLanguageCount": fast.count,
      "captureInterface": "macOS Screenshot",
      "networkRequired": false,
    ]
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    writeStandardOutput(try decodeUTF8(data) + "\n")
  }

  private func present(_ error: Error) {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    let recovery = (error as? LocalizedError)?.recoverySuggestion ?? ""
    if configuration.command != .capture {
      writeStandardError(message + (recovery.isEmpty ? "\n" : "\n\(recovery)\n"))
      terminate(code: 1)
      return
    }

    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = message
    alert.informativeText = recovery
    alert.runModal()
    terminate(code: 1)
  }

  private func terminate(code: Int32 = 0) {
    // AppKit terminates the process with status zero and does not return.
    if code != 0 { Foundation.exit(code) }
    NSApp.terminate(nil)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

private func writeStandardOutput(_ text: String) {
  FileHandle.standardOutput.write(Data(text.utf8))
}

private func writeStandardError(_ text: String) {
  FileHandle.standardError.write(Data(text.utf8))
}

private func decodeUTF8(_ data: Data) throws -> String {
  guard let text = String(bytes: data, encoding: .utf8) else {
    throw OCRCaptureError.outputFailed("an encoder returned invalid UTF-8")
  }
  return text
}
