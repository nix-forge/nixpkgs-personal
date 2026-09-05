import Foundation

enum OCRRenderer {
  static func render(_ result: OCRResult, as mode: RenderMode) -> String {
    if mode == .table, let native = result.nativeTableTSV, !native.isEmpty { return native }
    if mode == .raw, let transcript = result.structuredDocument?.transcript, !transcript.isEmpty {
      return transcript
    }
    if mode == .paragraph,
      let document = result.structuredDocument,
      !document.root.descendants(of: .paragraph).isEmpty
    {
      return document.root.descendants(of: .paragraph)
        .compactMap(\.transcript)
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
    if mode == .markdown, let document = result.structuredDocument {
      return renderMarkdown(document.root)
    }
    let observations = result.observations.filter {
      !($0.best?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    switch mode {
    case .raw: return observations.compactMap(\.best?.text).joined(separator: "\n")
    case .lines: return renderLines(cluster(observations))
    case .paragraph: return renderParagraphs(cluster(observations))
    case .code: return renderCode(cluster(observations))
    case .table: return renderTable(cluster(observations))
    case .markdown: return renderParagraphs(cluster(observations))
    }
  }

  static func averageConfidence(_ observations: [OCRObservation]) -> Float {
    let values = observations.compactMap(\.best?.confidence)
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Float(values.count)
  }

  struct Row: Equatable {
    var observations: [OCRObservation]
    var centerY: Double
    var height: Double
  }

  static func cluster(_ observations: [OCRObservation]) -> [Row] {
    let sorted = observations.sorted {
      let delta = abs($0.boundingBox.top - $1.boundingBox.top)
      if delta > max($0.boundingBox.height, $1.boundingBox.height) * 0.35 {
        return $0.boundingBox.top > $1.boundingBox.top
      }
      return $0.boundingBox.x < $1.boundingBox.x
    }
    var rows: [Row] = []
    for observation in sorted {
      let box = observation.boundingBox
      let centerY = box.y + box.height / 2
      let bestIndex = rows.indices.min { lhs, rhs in
        abs(rows[lhs].centerY - centerY) < abs(rows[rhs].centerY - centerY)
      }
      if let index = bestIndex,
        abs(rows[index].centerY - centerY) <= max(rows[index].height, box.height) * 0.55
      {
        rows[index].observations.append(observation)
        let count = Double(rows[index].observations.count)
        rows[index].centerY = ((rows[index].centerY * (count - 1)) + centerY) / count
        rows[index].height = max(rows[index].height, box.height)
      } else {
        rows.append(Row(observations: [observation], centerY: centerY, height: box.height))
      }
    }
    return rows.sorted { $0.centerY > $1.centerY }.map { row in
      var copy = row
      let rightToLeft =
        copy.observations.filter { isRightToLeft($0.best?.text ?? "") }.count
        > copy.observations.count / 2
      copy.observations.sort {
        rightToLeft
          ? $0.boundingBox.x > $1.boundingBox.x
          : $0.boundingBox.x < $1.boundingBox.x
      }
      return copy
    }
  }

  private static func isRightToLeft(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x0590...0x08ff, 0xfb1d...0xfdff, 0xfe70...0xfefc:
        return true
      case 0x0041...0x005a, 0x0061...0x007a, 0x00c0...0x02af, 0x3040...0xd7af:
        return false
      default:
        continue
      }
    }
    return false
  }

  private static func rowText(_ row: Row) -> String {
    row.observations.compactMap(\.best?.text).joined(separator: " ")
  }

  private static func renderLines(_ rows: [Row]) -> String {
    guard !rows.isEmpty else { return "" }
    var output: [String] = []
    for index in rows.indices {
      if index > 0 {
        let gap = rows[index - 1].centerY - rows[index].centerY
        if gap > max(rows[index - 1].height, rows[index].height) * 1.8 { output.append("") }
      }
      output.append(rowText(rows[index]))
    }
    return output.joined(separator: "\n")
  }

  private static func renderParagraphs(_ rows: [Row]) -> String {
    guard !rows.isEmpty else { return "" }
    var paragraphs: [String] = []
    var current = ""
    for index in rows.indices {
      let line = rowText(rows[index]).trimmingCharacters(in: .whitespaces)
      let largeGap =
        index > 0
        && rows[index - 1].centerY - rows[index].centerY > max(
          rows[index - 1].height, rows[index].height) * 1.7
      let startsList = line.range(of: #"^(?:[-*•]|\d+[.)])\s"#, options: .regularExpression) != nil
      if largeGap || startsList {
        if !current.isEmpty { paragraphs.append(current) }
        current = line
      } else if current.isEmpty {
        current = line
      } else if shouldJoinWithoutSpace(current, line) {
        current += line
      } else if current.hasSuffix("-") && line.first?.isLowercase == true {
        current.removeLast()
        current += line
      } else {
        current += " " + line
      }
    }
    if !current.isEmpty { paragraphs.append(current) }
    return paragraphs.joined(separator: "\n\n")
  }

  private static func shouldJoinWithoutSpace(_ previous: String, _ next: String) -> Bool {
    guard let lhs = previous.unicodeScalars.last, let rhs = next.unicodeScalars.first else {
      return false
    }
    func isCJK(_ scalar: UnicodeScalar) -> Bool {
      (0x3040...0x30ff).contains(scalar.value) || (0x3400...0x9fff).contains(scalar.value)
        || (0xac00...0xd7af).contains(scalar.value)
    }
    return isCJK(lhs) && isCJK(rhs)
  }

  private static func renderCode(_ rows: [Row]) -> String {
    let nonempty = rows.flatMap(\.observations)
    guard let left = nonempty.map(\.boundingBox.x).min() else { return "" }
    let characterWidths = nonempty.compactMap { item -> Double? in
      guard let text = item.best?.text, !text.isEmpty else { return nil }
      return item.boundingBox.width / Double(max(text.count, 1))
    }.sorted()
    let unit = characterWidths.isEmpty ? 0.01 : characterWidths[characterWidths.count / 2]
    return rows.map { row in
      guard let first = row.observations.first else { return "" }
      let indentation = max(
        0, min(80, Int(((first.boundingBox.x - left) / max(unit, 0.002)).rounded())))
      return String(repeating: " ", count: indentation) + rowText(row)
    }.joined(separator: "\n")
  }

  private static func renderTable(_ rows: [Row]) -> String {
    guard !rows.isEmpty else { return "" }
    let allCenters = rows.flatMap { $0.observations.map(\.boundingBox.centerX) }.sorted()
    var columns: [Double] = []
    let tolerance = 0.045
    for center in allCenters {
      if let index = columns.indices.min(by: {
        abs(columns[$0] - center) < abs(columns[$1] - center)
      }),
        abs(columns[index] - center) < tolerance
      {
        columns[index] = (columns[index] + center) / 2
      } else {
        columns.append(center)
      }
    }
    columns.sort()
    return rows.map { row in
      var cells = Array(repeating: "", count: max(columns.count, 1))
      for item in row.observations {
        guard let text = item.best?.text,
          let index = columns.indices.min(by: {
            abs(columns[$0] - item.boundingBox.centerX)
              < abs(columns[$1] - item.boundingBox.centerX)
          })
        else { continue }
        cells[index] = cells[index].isEmpty ? text : cells[index] + " " + text
      }
      while cells.last?.isEmpty == true { cells.removeLast() }
      return cells.joined(separator: "\t")
    }.joined(separator: "\n")
  }

  private static func renderMarkdown(_ root: OCRDocumentNode) -> String {
    let documents = root.children.filter { $0.kind == .document }
    let rendered = (documents.isEmpty ? [root] : documents).compactMap(renderMarkdownDocument)
    return rendered.joined(separator: "\n\n---\n\n")
  }

  private static func renderMarkdownDocument(_ document: OCRDocumentNode) -> String? {
    let structural = document.children.filter {
      $0.kind == .title || $0.kind == .table || $0.kind == .list
    }
    let semantic = document.children.filter {
      $0.kind == .title || $0.kind == .paragraph || $0.kind == .table || $0.kind == .list
    }.filter { candidate in
      guard candidate.kind == .paragraph else { return true }
      return !structural.contains { structure in
        structure.transcript == candidate.transcript
          || substantiallyContains(structure.boundingBox, candidate.boundingBox)
      }
    }.sorted { lhs, rhs in
      let lhsTop = lhs.boundingBox?.top ?? 0
      let rhsTop = rhs.boundingBox?.top ?? 0
      if abs(lhsTop - rhsTop) > 0.01 { return lhsTop > rhsTop }
      return (lhs.boundingBox?.x ?? 0) < (rhs.boundingBox?.x ?? 0)
    }
    let blocks = semantic.compactMap(renderMarkdownNode)
    if !blocks.isEmpty { return blocks.joined(separator: "\n\n") }
    return document.transcript?.nilIfEmpty
  }

  private static func renderMarkdownNode(_ node: OCRDocumentNode) -> String? {
    switch node.kind {
    case .title:
      return node.transcript?.nilIfEmpty.map { "# \($0)" }
    case .paragraph:
      return node.transcript?.nilIfEmpty
    case .list:
      let items = node.children.filter { $0.kind == .listItem }
      let rendered = items.compactMap { item -> String? in
        guard let text = item.transcript?.nilIfEmpty else { return nil }
        let markerType = item.attributes["markerType"] ?? ""
        let detectedMarker = item.attributes["marker"]?.trimmingCharacters(in: .whitespaces)
        let marker =
          detectedMarker?.nilIfEmpty
          ?? (markerType.contains("decimal") || markerType.contains("latin") ? "1." : "-")
        return "\(marker) \(text)"
      }
      return rendered.isEmpty ? nil : rendered.joined(separator: "\n")
    case .table:
      let rows = node.children.filter { $0.kind == .tableRow }.map { row in
        row.children.filter { $0.kind == .tableCell }.map {
          escapeMarkdownTableCell($0.transcript ?? "")
        }
      }.filter { !$0.isEmpty }
      guard let first = rows.first else { return nil }
      let width = rows.map(\.count).max() ?? first.count
      func padded(_ row: [String]) -> [String] {
        row + Array(repeating: "", count: max(0, width - row.count))
      }
      var lines = ["| " + padded(first).joined(separator: " | ") + " |"]
      lines.append("| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |")
      lines += rows.dropFirst().map { "| " + padded($0).joined(separator: " | ") + " |" }
      return lines.joined(separator: "\n")
    default:
      return node.transcript?.nilIfEmpty
    }
  }

  private static func escapeMarkdownTableCell(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "|", with: "\\|")
      .replacingOccurrences(of: "\n", with: "<br>")
  }

  private static func substantiallyContains(
    _ outer: NormalizedBox?,
    _ inner: NormalizedBox?
  ) -> Bool {
    guard let outer, let inner else { return false }
    let intersection = outer.cgRect.intersection(inner.cgRect)
    let innerArea = inner.width * inner.height
    guard !intersection.isNull, innerArea > 0 else { return false }
    return (intersection.width * intersection.height) / innerArea >= 0.72
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
