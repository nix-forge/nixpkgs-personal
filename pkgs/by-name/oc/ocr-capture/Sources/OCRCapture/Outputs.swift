import AppKit
import Foundation

@MainActor
final class ClipboardWriter {
  private let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func write(_ text: String) throws {
    pasteboard.prepareForNewContents()
    guard pasteboard.writeObjects([text as NSString]), pasteboard.string(forType: .string) == text
    else {
      throw OCRCaptureError.clipboardFailed
    }
  }
}

enum FileOutput {
  static func write(_ text: String, to path: String, append: Bool) throws {
    let url = URL(fileURLWithPath: path)
    let payload = Data((text + (text.hasSuffix("\n") ? "" : "\n")).utf8)
    do {
      if append {
        if !FileManager.default.fileExists(atPath: path) {
          FileManager.default.createFile(
            atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
      } else {
        try payload.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
      }
    } catch {
      throw OCRCaptureError.outputFailed(error.localizedDescription)
    }
  }
}
