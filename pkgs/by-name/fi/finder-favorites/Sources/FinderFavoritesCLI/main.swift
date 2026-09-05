import Darwin
import FinderFavoritesCore
import Foundation

private let version = "0.1.0"

private struct Options {
  var command: String
  var configPath: String?
  var stateDirectory: String?
  var json = false
  var dryRun = false
}

private struct DoctorReport: Codable {
  let schemaVersion: Int
  let version: String
  let architecture: String
  let macOSVersion: String
  let backend: String
  let backendDeprecated: Bool
  let runningAsRoot: Bool
  let warning: String
}

@main
private enum FinderFavoritesCommand {
  static func main() {
    do {
      let options = try parse(Array(ProcessArguments.current.dropFirst()))
      try run(options)
    } catch {
      writeError("finder-favorites: \(error)")
      Darwin.exit(2)
    }
  }

  private static func run(_ options: Options) throws {
    if options.command == "help" {
      print(help)
      return
    }
    if options.command == "version" {
      print("finder-favorites \(version)")
      return
    }
    if options.command == "doctor" {
      let report = DoctorReport(
        schemaVersion: 1,
        version: version,
        architecture: architecture,
        macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        backend: "LSSharedFileList",
        backendDeprecated: true,
        runningAsRoot: getuid() == 0 || geteuid() == 0,
        warning: "Apple provides no supported programmatic Finder Favorites API. "
          + "This tool isolates the deprecated API behind a transactional adapter."
      )
      if options.json {
        print(try StableJSON.string(for: report))
      } else {
        print("finder-favorites \(version)")
        print("architecture: \(report.architecture)")
        print("macOS: \(report.macOSVersion)")
        print("backend: \(report.backend) (deprecated by Apple)")
        print("warning: \(report.warning)")
      }
      return
    }

    let engine = FavoritesEngine(
      backend: LegacySharedFileListBackend(),
      stateDirectory: stateDirectory(from: options)
    )
    switch options.command {
    case "list":
      let snapshot = try engine.list()
      if options.json {
        print(try StableJSON.string(for: snapshot))
      } else if snapshot.items.isEmpty {
        print("No Finder favorites found.")
      } else {
        for item in snapshot.items {
          print("\(item.itemID)\t\(item.label)\t\(item.path ?? "<unresolved>")")
        }
      }
    case "export":
      print(try StableJSON.string(for: engine.exportConfiguration()))
    case "plan":
      let plan = try engine.plan(configuration: loadConfiguration(options))
      if options.json {
        print(try StableJSON.string(for: plan))
      } else {
        printPlan(plan)
      }
    case "check":
      let plan = try engine.plan(configuration: loadConfiguration(options))
      if options.json {
        print(try StableJSON.string(for: plan))
      } else {
        printPlan(plan)
      }
      if plan.hasChanges {
        Darwin.exit(1)
      }
    case "apply":
      let result = try engine.apply(
        configuration: loadConfiguration(options),
        dryRun: options.dryRun
      )
      if options.json {
        print(try StableJSON.string(for: result))
      } else if result.dryRun {
        print("Dry run: \(result.operationCount) operation(s) would be applied.")
      } else if result.changed {
        print("Applied Finder favorites configuration and verified the result.")
      } else {
        print("Finder favorites already match the configuration.")
      }
      for warning in result.warnings {
        writeError("warning: \(warning)")
      }
    case "recover":
      try engine.recover()
      print("Recovery complete. No unfinished transaction remains.")
    default:
      throw FinderFavoritesError.invalidConfiguration(
        "unknown command `\(options.command)`; run `finder-favorites help`"
      )
    }
  }

  private static func parse(_ arguments: [String]) throws -> Options {
    if arguments.isEmpty {
      return Options(command: "help")
    }
    if arguments == ["--help"] || arguments == ["-h"] {
      return Options(command: "help")
    }
    if arguments == ["--version"] {
      return Options(command: "version")
    }

    var options = Options(command: arguments[0])
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--help", "-h":
        return Options(command: "help")
      case "--json":
        options.json = true
      case "--dry-run":
        options.dryRun = true
      case "--config":
        index += 1
        guard index < arguments.count else {
          throw FinderFavoritesError.invalidConfiguration("--config requires a path")
        }
        options.configPath = arguments[index]
      case "--state-directory":
        index += 1
        guard index < arguments.count else {
          throw FinderFavoritesError.invalidConfiguration("--state-directory requires a path")
        }
        options.stateDirectory = arguments[index]
      default:
        throw FinderFavoritesError.invalidConfiguration(
          "unknown option `\(arguments[index])`"
        )
      }
      index += 1
    }

    if options.dryRun && options.command != "apply" {
      throw FinderFavoritesError.invalidConfiguration("--dry-run is valid only with apply")
    }
    return options
  }

  private static func loadConfiguration(_ options: Options) throws -> FavoritesConfiguration {
    guard let configPath = options.configPath else {
      throw FinderFavoritesError.invalidConfiguration("--config is required")
    }
    return try ConfigurationLoader.load(from: URL(fileURLWithPath: configPath))
  }

  private static func stateDirectory(from options: Options) -> URL {
    if let explicit = options.stateDirectory {
      return URL(fileURLWithPath: explicit)
    }
    if let xdgState = ProcessInfo.processInfo.environment["XDG_STATE_HOME"],
      !xdgState.isEmpty
    {
      return URL(fileURLWithPath: xdgState).appendingPathComponent("finder-favorites")
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local/state/finder-favorites")
  }

  private static func printPlan(_ plan: ReconciliationPlan) {
    if plan.operations.isEmpty {
      print("No changes required.")
    } else {
      print("Planned operations:")
      for operation in plan.operations {
        switch operation.kind {
        case .createDirectory:
          print("  create directory  \(operation.path ?? "")")
        case .add:
          print("  add               \(operation.label ?? "") -> \(operation.path ?? "")")
        case .placeBlock:
          print("  place block       \(operation.label ?? "") at \(operation.destination ?? "")")
        }
      }
    }
    for warning in plan.warnings {
      writeError("warning: \(warning)")
    }
  }

  private static var architecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }

  private static let help = """
    Manage Finder Favorites declaratively on modern macOS.

    USAGE
      finder-favorites list [--json]
      finder-favorites export
      finder-favorites plan --config FILE [--json]
      finder-favorites check --config FILE [--json]
      finder-favorites apply --config FILE [--dry-run] [--json]
      finder-favorites recover [--state-directory DIR]
      finder-favorites doctor [--json]
      finder-favorites version

    SAFETY
      apply is additive: it never removes unrelated favorites. It uses a
      per-user lock, a crash-recovery journal, rollback, and post-write
      verification. Apple has deprecated the underlying LSSharedFileList API
      and provides no supported replacement for Finder Favorites automation.
    """
}
