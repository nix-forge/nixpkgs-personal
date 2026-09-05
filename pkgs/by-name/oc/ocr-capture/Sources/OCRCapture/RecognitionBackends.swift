import CoreGraphics
import Foundation
import ImageIO

#if compiler(>=6.2)
  // Vision is not yet annotated as memory-safe; requests remain isolated behind this adapter.
  @preconcurrency @unsafe import Vision
#else
  @preconcurrency import Vision
#endif

#if OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION || (compiler(>=6.2) && !OCR_CAPTURE_NIX_BUILD)
  import DataDetection
#endif

final class LegacyTextRecognitionBackend: @unchecked Sendable {
  private let queue = DispatchQueue(label: "dev.ianmh.ocr-capture.vision", qos: .userInitiated)
  private let requestLock = NSLock()
  private var activeRequests: [VNRequest] = []

  func supportedLanguages(for mode: RecognitionMode) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = mode == .fast ? .fast : .accurate
    request.revision = VNRecognizeTextRequestRevision3
    return try request.supportedRecognitionLanguages().sorted()
  }

  func recognize(
    _ prepared: PreparedImage,
    configuration: OCRConfiguration,
    mode: RecognitionMode
  ) async throws -> OCRResult {
    let supported = try supportedLanguages(for: mode)
    for language in configuration.languages where !supported.contains(language) {
      throw OCRCaptureError.unsupportedLanguage(language, supported)
    }

    let started = ContinuousClock.now
    let textRequest = VNRecognizeTextRequest()
    textRequest.recognitionLevel = mode == .fast ? .fast : .accurate
    textRequest.usesLanguageCorrection = configuration.usesLanguageCorrection
    textRequest.customWords = configuration.customWords
    textRequest.minimumTextHeight =
      configuration.smallText
      ? min(configuration.minimumTextHeight, 0.005)
      : configuration.minimumTextHeight
    if configuration.languages.isEmpty {
      textRequest.automaticallyDetectsLanguage = true
    } else {
      textRequest.recognitionLanguages = configuration.languages
    }

    let allRequests: [VNRequest] = [textRequest]
    setActive(allRequests)
    defer { setActive([]) }

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async {
          do {
            let handler = VNImageRequestHandler(
              cgImage: prepared.image,
              orientation: configuration.orientation.cgImagePropertyOrientation,
              options: [:]
            )
            try handler.perform(allRequests)
            continuation.resume()
          } catch {
            if (error as NSError).code == NSUserCancelledError {
              continuation.resume(throwing: CancellationError())
            } else {
              continuation.resume(
                throwing: OCRCaptureError.recognitionFailed(error.localizedDescription))
            }
          }
        }
      }
    } onCancel: { [weak self] in
      self?.cancel()
    }

    let observations = (textRequest.results ?? []).compactMap { observation -> OCRObservation? in
      let candidates = observation.topCandidates(configuration.maximumCandidates).enumerated().map {
        index, candidate in
        OCRCandidate(text: candidate.string, confidence: candidate.confidence, rank: index)
      }
      guard !candidates.isEmpty else { return nil }
      return OCRObservation(
        candidates: candidates, boundingBox: NormalizedBox(observation.boundingBox))
    }
    return OCRResult(
      observations: observations,
      sourceWidth: prepared.image.width,
      sourceHeight: prepared.image.height,
      scaleApplied: prepared.scaleApplied,
      elapsedSeconds: Self.elapsed(since: started),
      nativeTableTSV: nil,
      backend: .legacyText
    )
  }

  func cancel() {
    requestLock.lock()
    let requests = activeRequests
    requestLock.unlock()
    for request in requests { request.cancel() }
  }

  private func setActive(_ requests: [VNRequest]) {
    requestLock.lock()
    activeRequests = requests
    requestLock.unlock()
  }

  private static func elapsed(since started: ContinuousClock.Instant) -> Double {
    let elapsed = started.duration(to: .now)
    return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
  }
}

enum DocumentRecognitionCapability {
  static var isCompiled: Bool {
    #if OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION || (compiler(>=6.2) && !OCR_CAPTURE_NIX_BUILD)
      true
    #else
      false
    #endif
  }

  static var isAvailable: Bool {
    guard isCompiled else { return false }
    if #available(macOS 26.0, *) { return true }
    return false
  }

  static let unavailableMessage =
    "Structured document recognition requires macOS 26 and a build made with the macOS 26 Vision SDK."
}

#if OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION || (compiler(>=6.2) && !OCR_CAPTURE_NIX_BUILD)
  @available(macOS 26.0, *)
  final class DocumentRecognitionBackend: @unchecked Sendable {
    func supportedLanguages(for _: RecognitionMode) throws -> [String] {
      RecognizeDocumentsRequest().supportedRecognitionLanguages
        .map(\.minimalIdentifier)
        .sorted()
    }

    func recognize(
      _ prepared: PreparedImage,
      configuration: OCRConfiguration,
      mode: RecognitionMode
    ) async throws -> OCRResult {
      let supported = try supportedLanguages(for: mode)
      for language in configuration.languages where !supported.contains(language) {
        throw OCRCaptureError.unsupportedLanguage(language, supported)
      }

      let started = ContinuousClock.now
      var request = RecognizeDocumentsRequest()
      request.textRecognitionOptions.customWords = configuration.customWords
      request.textRecognitionOptions.maximumCandidateCount = configuration.maximumCandidates
      request.textRecognitionOptions.minimumTextHeightFraction =
        configuration.smallText
        ? min(configuration.minimumTextHeight, 0.005)
        : configuration.minimumTextHeight
      request.textRecognitionOptions.useLanguageCorrection = configuration.usesLanguageCorrection
      request.textRecognitionOptions.automaticallyDetectLanguage = configuration.languages.isEmpty
      request.textRecognitionOptions.recognitionLanguages = configuration.languages.map {
        Locale.Language(identifier: $0)
      }
      let documents: [DocumentObservation]
      do {
        documents = try await request.perform(
          on: prepared.image,
          orientation: configuration.orientation.cgImagePropertyOrientation
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw OCRCaptureError.recognitionFailed(error.localizedDescription)
      }

      let observations = documents.flatMap { document in
        document.document.text.lines.compactMap {
          Self.textObservation($0, maximumCandidates: configuration.maximumCandidates)
        }
      }
      let tableTSV = documents.flatMap { Self.tables(in: $0.document) }
        .map(Self.renderTSV)
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
      let transcript = documents.map(\.document.text.transcript)
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
      let confidence =
        documents.isEmpty
        ? 0
        : documents.map(\.confidence).reduce(0, +) / Float(documents.count)
      let root = OCRDocumentNode(
        kind: .document,
        transcript: transcript,
        confidence: confidence,
        attributes: ["documentCount": String(documents.count)],
        children: documents.map {
          Self.containerNode(
            $0.document,
            kind: .document,
            maximumCandidates: configuration.maximumCandidates
          )
        }
      )

      return OCRResult(
        observations: observations,
        sourceWidth: prepared.image.width,
        sourceHeight: prepared.image.height,
        scaleApplied: prepared.scaleApplied,
        elapsedSeconds: Self.elapsed(since: started),
        nativeTableTSV: tableTSV.isEmpty ? nil : tableTSV,
        backend: .document,
        structuredDocument: OCRStructuredDocument(
          transcript: transcript,
          confidence: confidence,
          root: root
        )
      )
    }

    private static func containerNode(
      _ container: DocumentObservation.Container,
      kind: OCRDocumentNodeKind,
      maximumCandidates: Int
    ) -> OCRDocumentNode {
      var children: [OCRDocumentNode] = []
      if let title = container.title {
        children.append(textNode(title, kind: .title, maximumCandidates: maximumCandidates))
      }
      children.append(
        textNode(container.text, kind: .body, maximumCandidates: maximumCandidates))
      children += container.paragraphs.map {
        textNode($0, kind: .paragraph, maximumCandidates: maximumCandidates)
      }
      children += container.tables.map {
        tableNode($0, maximumCandidates: maximumCandidates)
      }
      children += container.lists.map {
        listNode($0, maximumCandidates: maximumCandidates)
      }
      return OCRDocumentNode(
        kind: kind,
        transcript: container.text.transcript,
        boundingBox: box(container.boundingRegion),
        boundingPolygon: polygon(container.boundingRegion),
        children: children
      )
    }

    private static func textNode(
      _ text: DocumentObservation.Container.Text,
      kind: OCRDocumentNodeKind,
      maximumCandidates: Int
    ) -> OCRDocumentNode {
      var attributes: [String: String] = [:]
      if let alignment = text.textAlignment {
        attributes["alignment"] = alignmentName(alignment)
      }
      var children = text.detectedData.map(detectedDataNode)
      children += text.lines.compactMap {
        observationNode($0, kind: .line, maximumCandidates: maximumCandidates)
      }
      if let words = text.words {
        children += words.compactMap {
          observationNode($0, kind: .word, maximumCandidates: maximumCandidates)
        }
      }
      return OCRDocumentNode(
        kind: kind,
        transcript: text.transcript,
        boundingBox: box(text.boundingRegion),
        boundingPolygon: polygon(text.boundingRegion),
        attributes: attributes,
        children: children
      )
    }

    private static func observationNode(
      _ observation: RecognizedTextObservation,
      kind: OCRDocumentNodeKind,
      maximumCandidates: Int
    ) -> OCRDocumentNode? {
      guard
        let converted = textObservation(
          observation, maximumCandidates: maximumCandidates)
      else { return nil }
      var attributes: [String: String] = [
        "isTitle": String(observation.isTitle),
        "recognitionLanguages": observation.recognitionLanguages.map(\.minimalIdentifier)
          .joined(separator: ","),
      ]
      if let wraps = observation.shouldWrapToNextLine {
        attributes["shouldWrapToNextLine"] = String(wraps)
      }
      if let direction = observation.textDirection {
        attributes["textDirection"] = directionName(direction)
      }
      return OCRDocumentNode(
        kind: kind,
        transcript: observation.transcript,
        boundingBox: converted.boundingBox,
        boundingPolygon: converted.boundingPolygon,
        confidence: converted.best?.confidence,
        candidates: converted.candidates,
        attributes: attributes
      )
    }

    private static func textObservation(
      _ observation: RecognizedTextObservation,
      maximumCandidates: Int
    ) -> OCRObservation? {
      let candidates = observation.topCandidates(maximumCandidates).enumerated().map {
        index, candidate in
        OCRCandidate(text: candidate.string, confidence: candidate.confidence, rank: index)
      }
      guard !candidates.isEmpty else { return nil }
      return OCRObservation(
        candidates: candidates,
        boundingBox: NormalizedBox(observation.boundingRegion.boundingBox.cgRect),
        boundingPolygon: polygon(observation.boundingRegion),
        recognitionLanguages: observation.recognitionLanguages.map(\.minimalIdentifier),
        isTitle: observation.isTitle,
        shouldWrapToNextLine: observation.shouldWrapToNextLine,
        textDirection: observation.textDirection.map(directionName)
      )
    }

    // Vision models each semantic type as an enum case. Keeping this conversion
    // exhaustive makes additions fail review instead of disappearing silently.
    // swiftlint:disable:next cyclomatic_complexity
    private static func detectedDataNode(
      _ detected: DocumentObservation.Container.DataDetectorMatch
    ) -> OCRDocumentNode {
      var attributes: [String: String] = [:]
      let transcript: String
      switch detected.match.details {
      case .link(let value):
        attributes["semanticType"] = "link"
        transcript = value.url.absoluteString
      case .emailAddress(let value):
        attributes["semanticType"] = "emailAddress"
        if let label = value.label { attributes["label"] = label }
        transcript = value.emailAddress
      case .phoneNumber(let value):
        attributes["semanticType"] = "phoneNumber"
        if let label = value.label { attributes["label"] = label }
        transcript = value.phoneNumber
      case .postalAddress(let value):
        attributes["semanticType"] = "postalAddress"
        if let value = value.street { attributes["street"] = value }
        if let value = value.city { attributes["city"] = value }
        if let value = value.state { attributes["state"] = value }
        if let value = value.postalCode { attributes["postalCode"] = value }
        if let value = value.region { attributes["region"] = value }
        if let value = value.regionCode { attributes["regionCode"] = value.identifier }
        if let value = value.label { attributes["label"] = value }
        transcript = value.fullAddress
      case .calendarEvent(let value):
        attributes["semanticType"] = "calendarEvent"
        attributes["allDay"] = String(value.allDay)
        if let date = value.startDate {
          attributes["startDate"] = ISO8601DateFormatter().string(from: date)
        }
        if let zone = value.startTimeZone { attributes["startTimeZone"] = zone.identifier }
        if let date = value.endDate {
          attributes["endDate"] = ISO8601DateFormatter().string(from: date)
        }
        if let zone = value.endTimeZone { attributes["endTimeZone"] = zone.identifier }
        transcript = attributes["startDate"] ?? "calendar event"
      case .moneyAmount(let value):
        attributes["semanticType"] = "moneyAmount"
        attributes["currency"] = value.currency.identifier
        transcript = NSDecimalNumber(decimal: value.amount).stringValue
      case .flightNumber(let value):
        attributes["semanticType"] = "flightNumber"
        attributes["airlineCode"] = value.airlineCode
        transcript = "\(value.airlineCode)\(value.flightNumber)"
      case .shipmentTrackingNumber(let value):
        attributes["semanticType"] = "shipmentTrackingNumber"
        attributes["carrier"] = value.carrier
        if let url = value.trackingURL { attributes["trackingURL"] = url.absoluteString }
        transcript = value.trackingNumber
      case .measurement(let value):
        attributes["semanticType"] = "measurement"
        attributes["possibleDimensions"] = value.possibleDimensions.map {
          "\(String(reflecting: type(of: $0))):\($0.symbol)"
        }.joined(separator: ",")
        transcript = String(value.value)
      case .paymentIdentifier(let value):
        attributes["semanticType"] = "paymentIdentifier"
        attributes["paymentSystem"] = paymentSystemName(value.type)
        transcript = value.identifier
      @unknown default:
        attributes["semanticType"] = "unknown"
        transcript = ""
      }
      return OCRDocumentNode(
        kind: .detectedData,
        transcript: transcript,
        boundingBox: box(detected.boundingRegion),
        boundingPolygon: polygon(detected.boundingRegion),
        attributes: attributes
      )
    }

    private static func tableNode(
      _ table: DocumentObservation.Container.Table,
      maximumCandidates: Int
    ) -> OCRDocumentNode {
      let rows = table.rows.enumerated().map { rowIndex, row in
        OCRDocumentNode(
          kind: .tableRow,
          attributes: ["rowIndex": String(rowIndex)],
          children: row.map { cell in
            OCRDocumentNode(
              kind: .tableCell,
              transcript: cell.content.text.transcript,
              boundingBox: box(cell.content.boundingRegion),
              boundingPolygon: polygon(cell.content.boundingRegion),
              attributes: [
                "rowStart": String(cell.rowRange.lowerBound),
                "rowEnd": String(cell.rowRange.upperBound),
                "columnStart": String(cell.columnRange.lowerBound),
                "columnEnd": String(cell.columnRange.upperBound),
              ],
              children: containerNode(
                cell.content,
                kind: .tableCell,
                maximumCandidates: maximumCandidates
              ).children
            )
          }
        )
      }
      return OCRDocumentNode(
        kind: .table,
        boundingBox: box(table.boundingRegion),
        boundingPolygon: polygon(table.boundingRegion),
        attributes: [
          "rowCount": String(table.rows.count),
          "columnCount": String(table.columns.count),
        ],
        children: rows
      )
    }

    private static func listNode(
      _ list: DocumentObservation.Container.List,
      maximumCandidates: Int
    ) -> OCRDocumentNode {
      OCRDocumentNode(
        kind: .list,
        boundingBox: box(list.boundingRegion),
        boundingPolygon: polygon(list.boundingRegion),
        children: list.items.enumerated().map { index, item in
          var attributes = [
            "index": String(index),
            "marker": item.markerString,
          ]
          if let marker = item.markerType { attributes["markerType"] = markerName(marker) }
          return OCRDocumentNode(
            kind: .listItem,
            transcript: item.itemString,
            boundingBox: box(item.content.boundingRegion),
            boundingPolygon: polygon(item.content.boundingRegion),
            attributes: attributes,
            children: containerNode(
              item.content,
              kind: .listItem,
              maximumCandidates: maximumCandidates
            ).children
          )
        }
      )
    }

    private static func tables(
      in container: DocumentObservation.Container
    ) -> [DocumentObservation.Container.Table] {
      var result = container.tables
      for table in container.tables {
        for row in table.rows {
          for cell in row { result += tables(in: cell.content) }
        }
      }
      for list in container.lists {
        for item in list.items { result += tables(in: item.content) }
      }
      return result
    }

    private static func renderTSV(_ table: DocumentObservation.Container.Table) -> String {
      table.rows.map { row in
        row.map { $0.content.text.transcript.replacingOccurrences(of: "\t", with: " ") }
          .joined(separator: "\t")
      }.joined(separator: "\n")
    }

    private static func box(_ region: NormalizedRegion) -> NormalizedBox {
      NormalizedBox(region.boundingBox.cgRect)
    }

    private static func polygon(_ region: NormalizedRegion) -> [NormalizedPoint] {
      region.points.map { NormalizedPoint(x: $0.x, y: $0.y) }
    }

    private static func alignmentName(
      _ value: DocumentObservation.Container.Text.Alignment
    ) -> String {
      switch value {
      case .center: return "center"
      case .leading: return "leading"
      case .trailing: return "trailing"
      @unknown default: return "unknown"
      }
    }

    private static func directionName(_ value: RecognizedTextObservation.Direction) -> String {
      switch value {
      case .leftToRight: return "left-to-right"
      case .rightToLeft: return "right-to-left"
      case .topToBottom: return "top-to-bottom"
      @unknown default: return "unknown"
      }
    }

    private static func markerName(_ value: DocumentObservation.Container.List.Marker) -> String {
      switch value {
      case .bullet: return "bullet"
      case .hyphen: return "hyphen"
      case .lowercaseLatin: return "lowercase-latin"
      case .uppercaseLatin: return "uppercase-latin"
      case .decimal: return "decimal"
      case .decorativeDecimal: return "decorative-decimal"
      case .compositeDecimal: return "composite-decimal"
      @unknown default: return "unknown"
      }
    }

    private static func paymentSystemName(
      _ value: DataDetector.Match.SemanticDetails.PaymentIdentifier.PaymentSystem
    ) -> String {
      switch value {
      case .unifiedPaymentsInterface: return "unified-payments-interface"
      @unknown default: return "unknown"
      }
    }

    private static func elapsed(since started: ContinuousClock.Instant) -> Double {
      let elapsed = started.duration(to: .now)
      return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
  }
#endif
