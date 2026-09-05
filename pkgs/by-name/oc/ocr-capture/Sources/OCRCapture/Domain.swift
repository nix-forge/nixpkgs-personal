import CoreGraphics
import Foundation
import ImageIO

enum OCRCaptureError: LocalizedError, Equatable {
  case invalidArguments(String)
  case captureUnavailable(String)
  case captureFailed(String)
  case selectionCancelled
  case decodeFailed(String)
  case imageTooLarge(Int)
  case unsupportedLanguage(String, [String])
  case featureUnavailable(String)
  case recognitionFailed(String)
  case recognitionTimedOut(TimeInterval)
  case noText
  case clipboardFailed
  case outputFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let detail): return detail
    case .captureUnavailable(let detail): return "Screen capture is unavailable: \(detail)"
    case .captureFailed(let detail): return "Screen capture failed: \(detail)"
    case .selectionCancelled: return "Capture cancelled."
    case .decodeFailed(let detail): return "The image could not be decoded: \(detail)"
    case .imageTooLarge(let count): return "The image exceeds the input limit (\(count) bytes)."
    case .unsupportedLanguage(let language, _):
      return "Vision does not support \(language) for this recognition mode."
    case .featureUnavailable(let detail): return detail
    case .recognitionFailed(let detail): return "Text recognition failed: \(detail)"
    case .recognitionTimedOut(let seconds):
      return "Text recognition exceeded \(seconds.formatted()) seconds."
    case .noText: return "No text was found in the selected area."
    case .clipboardFailed: return "The recognized text could not be written to the clipboard."
    case .outputFailed(let detail): return "The result could not be written: \(detail)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .noText:
      return "Try a tighter selection, Accurate recognition, or the Small Text preset."
    case .unsupportedLanguage(_, let supported):
      return "Choose one of: \(supported.prefix(12).joined(separator: ", "))."
    case .recognitionTimedOut:
      return "Select a smaller area or use Fast recognition."
    case .featureUnavailable:
      return
        "Use Automatic or Legacy Text, or rebuild with a Swift and Apple SDK that include this feature."
    case .clipboardFailed:
      return "Try the capture again after checking clipboard access."
    default: return nil
    }
  }

  var isCancellation: Bool { self == .selectionCancelled }
}

enum RecognitionMode: String, Codable, CaseIterable, Sendable {
  case accurate
  case fast
  case adaptive
}

enum RecognitionBackendPreference: String, Codable, CaseIterable, Sendable {
  case automatic
  case legacy
  case document
}

enum RecognitionBackend: String, Codable, CaseIterable, Sendable {
  case legacyText = "legacy-text"
  case document
  case mixed
}

enum RenderMode: String, Codable, CaseIterable, Sendable {
  case raw
  case lines
  case paragraph
  case code
  case table
  case markdown
}

enum Destination: String, Codable, CaseIterable, Sendable {
  case clipboard
  case stdout
  case file
}

enum ImageOrientation: String, Codable, CaseIterable, Sendable {
  case up
  case upMirrored = "up-mirrored"
  case down
  case downMirrored = "down-mirrored"
  case left
  case leftMirrored = "left-mirrored"
  case right
  case rightMirrored = "right-mirrored"

  var cgImagePropertyOrientation: CGImagePropertyOrientation {
    switch self {
    case .up: return .up
    case .upMirrored: return .upMirrored
    case .down: return .down
    case .downMirrored: return .downMirrored
    case .left: return .left
    case .leftMirrored: return .leftMirrored
    case .right: return .right
    case .rightMirrored: return .rightMirrored
    }
  }
}

struct NormalizedBox: Codable, Equatable, Sendable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  init(_ rect: CGRect) {
    x = rect.origin.x
    y = rect.origin.y
    width = rect.width
    height = rect.height
  }

  var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
  var top: Double { y + height }
  var centerX: Double { x + width / 2 }
}

struct NormalizedPoint: Codable, Equatable, Sendable {
  let x: Double
  let y: Double
}

struct OCRCandidate: Codable, Equatable, Sendable {
  let text: String
  let confidence: Float
  let rank: Int
}

struct OCRObservation: Codable, Equatable, Sendable {
  let candidates: [OCRCandidate]
  let boundingBox: NormalizedBox
  var boundingPolygon: [NormalizedPoint]? = nil
  var recognitionLanguages: [String]? = nil
  var isTitle: Bool? = nil
  var shouldWrapToNextLine: Bool? = nil
  var textDirection: String? = nil

  var best: OCRCandidate? { candidates.first }
}

enum OCRDocumentNodeKind: String, Codable, CaseIterable, Sendable {
  case document
  case title
  case body
  case paragraph
  case line
  case word
  case detectedData = "detected-data"
  case table
  case tableRow = "table-row"
  case tableCell = "table-cell"
  case list
  case listItem = "list-item"
}

/// A lossless, backend-neutral representation of Vision's structured document tree.
/// Attributes retain API-specific metadata without coupling older SDK builds to macOS 26 types.
struct OCRDocumentNode: Codable, Equatable, Sendable {
  let kind: OCRDocumentNodeKind
  var transcript: String? = nil
  var boundingBox: NormalizedBox? = nil
  var boundingPolygon: [NormalizedPoint]? = nil
  var confidence: Float? = nil
  var candidates: [OCRCandidate]? = nil
  var attributes: [String: String] = [:]
  var children: [Self] = []

  func descendants(of kind: OCRDocumentNodeKind) -> [Self] {
    children.flatMap { child in
      (child.kind == kind ? [child] : []) + child.descendants(of: kind)
    }
  }
}

struct OCRStructuredDocument: Codable, Equatable, Sendable {
  let transcript: String
  let confidence: Float
  let root: OCRDocumentNode
}

struct OCRResult: Codable, Equatable, Sendable {
  let observations: [OCRObservation]
  let sourceWidth: Int
  let sourceHeight: Int
  let scaleApplied: Double
  let elapsedSeconds: Double
  let nativeTableTSV: String?
  var backend: RecognitionBackend = .legacyText
  var structuredDocument: OCRStructuredDocument? = nil
  var warnings: [String] = []
}

enum Command: Equatable, Sendable {
  case capture
  case image(String)
  case stdin
  case languages
  case diagnose
  case selftest
  case help
}

struct OCRConfiguration: Equatable, Sendable {
  var command: Command = .capture
  var recognitionMode: RecognitionMode = .accurate
  var recognitionBackend: RecognitionBackendPreference = .automatic
  var renderMode: RenderMode = .lines
  var destinations: Set<Destination> = [.clipboard]
  var languages: [String] = []
  var customWords: [String] = []
  var usesLanguageCorrection = true
  var minimumTextHeight: Float = 0
  var smallText = false
  var maximumPixels = 24_000_000
  var maximumInputBytes = 100 * 1_024 * 1_024
  var timeout: TimeInterval = 20
  var maximumCandidates = 3
  var orientation: ImageOrientation = .up
  var outputPath: String?
  var appendOutput = false
  var structuredJSON = false
}
