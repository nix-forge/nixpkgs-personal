import CoreGraphics
import Foundation
import ImageIO

struct PreparedImage: @unchecked Sendable {
  let image: CGImage
  let scaleApplied: Double
}

enum ImageLoader {
  static func fromFile(_ path: String, maximumBytes: Int) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw OCRCaptureError.decodeFailed("not a regular file")
    }
    if let size = values.fileSize, size > maximumBytes { throw OCRCaptureError.imageTooLarge(size) }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { throw OCRCaptureError.decodeFailed(path) }
    return image
  }

  static func fromStandardInput(maximumBytes: Int) throws -> CGImage {
    var data = Data()
    while let chunk = try FileHandle.standardInput.read(
      upToCount: min(1_048_576, maximumBytes + 1 - data.count)),
      !chunk.isEmpty
    {
      data.append(chunk)
      guard data.count <= maximumBytes else { throw OCRCaptureError.imageTooLarge(data.count) }
    }
    guard !data.isEmpty,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { throw OCRCaptureError.decodeFailed("standard input") }
    return image
  }
}

enum ImagePreprocessor {
  static func prepare(_ image: CGImage, maximumPixels: Int, smallText: Bool) throws -> PreparedImage
  {
    let pixels = image.width.multipliedReportingOverflow(by: image.height)
    guard !pixels.overflow else { throw OCRCaptureError.captureFailed("invalid image dimensions") }
    var targetScale = min(1, sqrt(Double(maximumPixels) / Double(max(pixels.partialValue, 1))))
    if smallText, targetScale == 1, pixels.partialValue <= maximumPixels / 4 {
      targetScale = min(2, sqrt(Double(maximumPixels) / Double(max(pixels.partialValue, 1))))
    }
    guard abs(targetScale - 1) > 0.01 else { return PreparedImage(image: image, scaleApplied: 1) }

    let width = max(1, Int((Double(image.width) * targetScale).rounded()))
    let height = max(1, Int((Double(image.height) * targetScale).rounded()))
    // The destination uses RGBA pixels even when the input is grayscale or CMYK.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    #if compiler(>=6.2)
      // A nil data pointer asks CoreGraphics to allocate and own the bitmap.
      let context = unsafe CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    #else
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    #endif
    guard
      let context
    else { throw OCRCaptureError.captureFailed("could not allocate the bounded image buffer") }
    context.interpolationQuality = smallText ? .high : .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage() else {
      throw OCRCaptureError.captureFailed("could not resize the image")
    }
    return PreparedImage(image: scaled, scaleApplied: targetScale)
  }
}

final class OCRService: @unchecked Sendable {
  private let legacy = LegacyTextRecognitionBackend()

  func supportedLanguages(
    for mode: RecognitionMode,
    backend preference: RecognitionBackendPreference = .automatic
  ) throws -> [String] {
    let prefersDocument = preference == .document || (preference == .automatic && mode != .fast)
    if prefersDocument {
      #if OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION || (compiler(>=6.2) && !OCR_CAPTURE_NIX_BUILD)
        if #available(macOS 26.0, *) {
          return try DocumentRecognitionBackend().supportedLanguages(for: mode)
        }
      #endif
      if preference == .document {
        throw OCRCaptureError.featureUnavailable(DocumentRecognitionCapability.unavailableMessage)
      }
    }
    return try legacy.supportedLanguages(for: mode)
  }

  func recognize(_ source: CGImage, configuration: OCRConfiguration) async throws -> OCRResult {
    let prepared = try ImagePreprocessor.prepare(
      source,
      maximumPixels: configuration.maximumPixels,
      smallText: configuration.smallText
    )
    return try await withThrowingTaskGroup(of: OCRResult.self) { group in
      group.addTask { [self] in try await performAdaptive(prepared, configuration: configuration) }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(configuration.timeout * 1_000_000_000))
        throw OCRCaptureError.recognitionTimedOut(configuration.timeout)
      }
      guard let first = try await group.next() else {
        throw OCRCaptureError.recognitionFailed("recognition ended without a result")
      }
      group.cancelAll()
      cancel()
      return first
    }
  }

  func cancel() {
    legacy.cancel()
  }

  private func performAdaptive(_ image: PreparedImage, configuration: OCRConfiguration) async throws
    -> OCRResult
  {
    if configuration.recognitionMode != .adaptive {
      return try await performBest(
        image, configuration: configuration, mode: configuration.recognitionMode)
    }
    if configuration.recognitionBackend == .document {
      return try await performBest(image, configuration: configuration, mode: .accurate)
    }
    let fastLanguages = try legacy.supportedLanguages(for: .fast)
    if configuration.languages.contains(where: { !fastLanguages.contains($0) }) {
      return try await performBest(image, configuration: configuration, mode: .accurate)
    }
    let fast = try await legacy.recognize(image, configuration: configuration, mode: .fast)
    if OCRRenderer.averageConfidence(fast.observations) >= 0.84, !fast.observations.isEmpty {
      return fast
    }
    return try await performBest(image, configuration: configuration, mode: .accurate)
  }

  private func performBest(
    _ prepared: PreparedImage,
    configuration: OCRConfiguration,
    mode: RecognitionMode
  ) async throws -> OCRResult {
    if configuration.recognitionBackend == .legacy || mode == .fast {
      if configuration.recognitionBackend == .document {
        return try await recognizeDocument(
          prepared, configuration: configuration, mode: mode, allowsFallback: false)
      }
      return try await legacy.recognize(prepared, configuration: configuration, mode: mode)
    }
    return try await recognizeDocument(
      prepared,
      configuration: configuration,
      mode: mode,
      allowsFallback: configuration.recognitionBackend == .automatic
    )
  }

  private func recognizeDocument(
    _ prepared: PreparedImage,
    configuration: OCRConfiguration,
    mode: RecognitionMode,
    allowsFallback: Bool
  ) async throws -> OCRResult {
    #if OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION || (compiler(>=6.2) && !OCR_CAPTURE_NIX_BUILD)
      if #available(macOS 26.0, *) {
        do {
          return try await DocumentRecognitionBackend().recognize(
            prepared, configuration: configuration, mode: mode)
        } catch  where allowsFallback {
          var fallback = try await legacy.recognize(
            prepared, configuration: configuration, mode: mode)
          fallback.warnings.append(
            "Structured document recognition failed; Legacy Text was used: \(error.localizedDescription)"
          )
          return fallback
        }
      }
    #endif
    guard allowsFallback else {
      throw OCRCaptureError.featureUnavailable(DocumentRecognitionCapability.unavailableMessage)
    }
    var fallback = try await legacy.recognize(
      prepared, configuration: configuration, mode: mode)
    fallback.warnings.append(
      "Structured document recognition is unavailable in this build; Legacy Text was used."
    )
    return fallback
  }
}
