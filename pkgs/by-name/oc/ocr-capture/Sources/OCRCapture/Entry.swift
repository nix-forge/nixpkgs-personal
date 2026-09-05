import AppKit
import Foundation

@main
enum OCRCaptureEntry {
  static let bundleIdentifier = "dev.ianmh.OCRCapture"

  @MainActor
  static func main() {
    let configuration: OCRConfiguration
    do {
      configuration = try ConfigurationParser.parse(
        Array(ProcessInfo.processInfo.arguments.dropFirst()))
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
      Foundation.exit(2)
    }

    // Keep non-UI verification usable in Nix's build sandbox, where AppKit's
    // system appearance resources are intentionally unavailable.
    if configuration.command == .help {
      FileHandle.standardOutput.write(Data((usage + "\n").utf8))
      Foundation.exit(0)
    }
    if configuration.command == .selftest {
      do {
        try OCRCaptureSelfTest.run()
        FileHandle.standardOutput.write(Data("OCR Capture self-test passed.\n".utf8))
        Foundation.exit(0)
      } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        Foundation.exit(1)
      }
    }

    var sessionLock: CaptureSessionLock?
    if configuration.command == .capture {
      do {
        guard let acquired = try CaptureSessionLock.acquire() else {
          Foundation.exit(0)
        }
        sessionLock = acquired
      } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        Foundation.exit(1)
      }
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = OCRCaptureApplication(configuration: configuration)
    application.delegate = delegate
    withExtendedLifetime(sessionLock) { application.run() }
  }
}
