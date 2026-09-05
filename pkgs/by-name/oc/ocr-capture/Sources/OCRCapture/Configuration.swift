import Foundation

enum ConfigurationParser {
  // A command-line option dispatcher is intentionally one exhaustive switch.
  // Splitting it into closures would hide argument mutation and validation.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  static func parse(_ rawArguments: [String]) throws -> OCRConfiguration {
    var configuration = OCRConfiguration()
    var arguments = rawArguments

    if let first = arguments.first, !first.hasPrefix("-") {
      arguments.removeFirst()
      switch first {
      case "capture": configuration.command = .capture
      case "image":
        guard let path = arguments.first, !path.hasPrefix("-") else {
          throw OCRCaptureError.invalidArguments("Usage: hm-ocr-capture image PATH [options]")
        }
        arguments.removeFirst()
        configuration.command = .image(path)
        configuration.destinations = [.stdout]
      case "stdin":
        configuration.command = .stdin
        configuration.destinations = [.stdout]
      case "languages": configuration.command = .languages
      case "diagnose": configuration.command = .diagnose
      case "help": configuration.command = .help
      case "selftest": configuration.command = .selftest
      default: throw OCRCaptureError.invalidArguments("Unknown command: \(first)")
      }
    }

    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      func value() throws -> String {
        let next = index + 1
        guard next < arguments.count else {
          throw OCRCaptureError.invalidArguments("Missing value after \(argument)")
        }
        index = next
        return arguments[next]
      }

      switch argument {
      case "--recognition":
        let raw = try value()
        guard let mode = RecognitionMode(rawValue: raw) else {
          throw invalidValue(raw, for: argument)
        }
        configuration.recognitionMode = mode
      case "--backend":
        let raw = try value()
        guard let backend = RecognitionBackendPreference(rawValue: raw) else {
          throw invalidValue(raw, for: argument)
        }
        configuration.recognitionBackend = backend
      case "--render":
        let raw = try value()
        guard let mode = RenderMode(rawValue: raw) else { throw invalidValue(raw, for: argument) }
        configuration.renderMode = mode
      case "--destination":
        let raw = try value()
        let values = raw.split(separator: ",").compactMap { Destination(rawValue: String($0)) }
        guard !values.isEmpty, values.count == raw.split(separator: ",").count else {
          throw invalidValue(raw, for: argument)
        }
        configuration.destinations = Set(values)
      case "--language": configuration.languages.append(try value())
      case "--custom-word": configuration.customWords.append(try value())
      case "--no-language-correction": configuration.usesLanguageCorrection = false
      case "--minimum-text-height":
        configuration.minimumTextHeight = try float(try value(), argument)
      case "--small-text": configuration.smallText = true
      case "--max-pixels": configuration.maximumPixels = try positiveInt(try value(), argument)
      case "--max-input-bytes":
        configuration.maximumInputBytes = try positiveInt(try value(), argument)
      case "--timeout": configuration.timeout = try positiveDouble(try value(), argument)
      case "--candidates":
        configuration.maximumCandidates = try boundedInt(try value(), argument, 1...10)
      case "--orientation":
        let raw = try value()
        guard let orientation = ImageOrientation(rawValue: raw) else {
          throw invalidValue(raw, for: argument)
        }
        configuration.orientation = orientation
      case "--output":
        configuration.outputPath = try value()
        configuration.destinations.insert(.file)
      case "--append": configuration.appendOutput = true
      case "--json": configuration.structuredJSON = true
      case "--help", "-h": configuration.command = .help
      default: throw OCRCaptureError.invalidArguments("Unknown option: \(argument)")
      }
      index += 1
    }

    guard configuration.minimumTextHeight >= 0, configuration.minimumTextHeight <= 1 else {
      throw OCRCaptureError.invalidArguments("--minimum-text-height must be between 0 and 1")
    }
    if configuration.destinations.contains(.file), configuration.outputPath == nil {
      throw OCRCaptureError.invalidArguments("--destination file requires --output PATH")
    }
    if configuration.appendOutput, configuration.outputPath == nil {
      throw OCRCaptureError.invalidArguments("--append requires --output PATH")
    }
    return configuration
  }

  private static func invalidValue(_ value: String, for option: String) -> OCRCaptureError {
    .invalidArguments("Invalid value for \(option): \(value)")
  }

  private static func positiveInt(_ value: String, _ option: String) throws -> Int {
    guard let number = Int(value), number > 0 else { throw invalidValue(value, for: option) }
    return number
  }

  private static func boundedInt(_ value: String, _ option: String, _ bounds: ClosedRange<Int>)
    throws -> Int
  {
    let number = try positiveInt(value, option)
    guard bounds.contains(number) else { throw invalidValue(value, for: option) }
    return number
  }

  private static func positiveDouble(_ value: String, _ option: String) throws -> Double {
    let number = try doubleValue(value, option)
    guard number > 0 else { throw invalidValue(value, for: option) }
    return number
  }

  private static func doubleValue(_ value: String, _ option: String) throws -> Double {
    guard let number = Double(value), number.isFinite, number >= 0 else {
      throw invalidValue(value, for: option)
    }
    return number
  }

  private static func float(_ value: String, _ option: String) throws -> Float {
    guard let number = Float(value), number.isFinite else { throw invalidValue(value, for: option) }
    return number
  }
}

let usage = """
  Usage:
    hm-ocr-capture capture [options]
    hm-ocr-capture image PATH [options]
    hm-ocr-capture stdin [options]
    hm-ocr-capture languages [--recognition accurate|fast]
    hm-ocr-capture diagnose

  Core options:
    capture                              Use the macOS region screenshot selector
    --recognition accurate|fast|adaptive  Vision quality/latency policy
    --backend automatic|legacy|document   Recognition implementation policy
    --render raw|lines|paragraph|code|table|markdown
    --language IDENTIFIER                 Repeat for preferred languages
    --custom-word WORD                    Repeat for domain vocabulary
    --no-language-correction              Disable Vision spelling correction
    --small-text                          Preserve smaller text at extra cost
    --minimum-text-height FRACTION        Ignore smaller text to reduce work
    --max-pixels COUNT                    Downscale before this pixel budget
    --max-input-bytes COUNT               Bound file and stdin input size
    --timeout SECONDS                     Cancel slow OCR work
    --candidates 1...10                   Retain alternate text candidates
    --orientation up|down|left|right      File/stdin image orientation
    --destination clipboard,stdout,file
    --output PATH [--append]              Explicit file destination
    --json                                Emit structured observations as JSON

  Region selection is the standard macOS Screenshot interaction: drag to
  select, press Escape to cancel, and hold Space while dragging to reposition.
  """
