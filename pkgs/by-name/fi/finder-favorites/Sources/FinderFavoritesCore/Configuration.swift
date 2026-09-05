import Foundation

public enum ConfigurationLoader {
  public static let maximumBytes = 1_048_576
  public static let maximumEntries = 256

  public static func load(from url: URL) throws -> FavoritesConfiguration {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw FinderFavoritesError.invalidConfiguration("\(url.path) is not a regular file")
    }
    guard let size = values.fileSize, size <= maximumBytes else {
      throw FinderFavoritesError.invalidConfiguration(
        "configuration exceeds the \(maximumBytes)-byte limit"
      )
    }

    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    try validateKnownKeys(data)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys
    let configuration: FavoritesConfiguration
    do {
      configuration = try decoder.decode(FavoritesConfiguration.self, from: data)
    } catch {
      throw FinderFavoritesError.invalidConfiguration(error.localizedDescription)
    }
    try validate(configuration)
    return configuration
  }

  public static func validate(_ configuration: FavoritesConfiguration) throws {
    guard configuration.schemaVersion == 1 else {
      throw FinderFavoritesError.invalidConfiguration(
        "unsupported schemaVersion \(configuration.schemaVersion); expected 1"
      )
    }
    guard configuration.entries.count <= maximumEntries else {
      throw FinderFavoritesError.invalidConfiguration(
        "entries exceeds the limit of \(maximumEntries)"
      )
    }

    var ids = Set<String>()
    var paths = Set<String>()
    for (index, entry) in configuration.entries.enumerated() {
      guard !entry.id.isEmpty else {
        throw FinderFavoritesError.invalidConfiguration("entries[\(index)].id is empty")
      }
      guard entry.id.utf8.count <= 128 else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)].id exceeds 128 UTF-8 bytes"
        )
      }
      guard hasNoControlCharacters(entry.id) else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)].id contains a control character"
        )
      }
      guard !entry.label.isEmpty else {
        throw FinderFavoritesError.invalidConfiguration("entries[\(index)].label is empty")
      }
      guard entry.label.utf8.count <= 1_024 else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)].label exceeds 1024 UTF-8 bytes"
        )
      }
      guard hasNoControlCharacters(entry.label) else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)].label contains a control character"
        )
      }
      guard entry.path.hasPrefix("/") else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)].path must be absolute"
        )
      }
      guard !entry.path.contains("\0") else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)].path contains a NUL byte"
        )
      }
      guard entry.path.utf8.count <= 4_096 else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)].path exceeds 4096 UTF-8 bytes"
        )
      }
      guard ids.insert(entry.id).inserted else {
        throw FinderFavoritesError.invalidConfiguration("duplicate entry id: \(entry.id)")
      }

      let canonical = canonicalPath(entry.path)
      guard paths.insert(canonical).inserted else {
        throw FinderFavoritesError.invalidConfiguration(
          "duplicate entry path after canonicalization: \(canonical)"
        )
      }
    }
  }

  static func prepare(
    _ configuration: FavoritesConfiguration,
    fileManager: FileManager = .default
  ) throws -> PreparedConfiguration {
    try validate(configuration)
    var entries: [PreparedEntry] = []
    var warnings: [String] = []

    for entry in configuration.entries {
      let canonical = canonicalPath(entry.path)
      var isDirectory: ObjCBool = false
      let exists = fileManager.fileExists(atPath: canonical, isDirectory: &isDirectory)
      if exists && !isDirectory.boolValue {
        throw FinderFavoritesError.invalidConfiguration(
          "\(entry.path) exists but is not a directory"
        )
      }
      if !exists {
        switch entry.onMissing {
        case .error:
          throw FinderFavoritesError.invalidConfiguration(
            "\(entry.path) does not exist (entry \(entry.id))"
          )
        case .skip:
          warnings.append("skipping missing directory \(entry.path) (entry \(entry.id))")
          continue
        case .createDirectory:
          break
        }
      }
      entries.append(PreparedEntry(desired: entry, canonicalPath: canonical, exists: exists))
    }
    return PreparedConfiguration(
      placement: configuration.placement,
      entries: entries,
      warnings: warnings
    )
  }

  static func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func validateKnownKeys(_ data: Data) throws {
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw FinderFavoritesError.invalidConfiguration(error.localizedDescription)
    }
    guard let root = object as? [String: Any] else {
      throw FinderFavoritesError.invalidConfiguration("the JSON root must be an object")
    }
    let rootKeys: Set<String> = ["schemaVersion", "placement", "entries"]
    let unknownRootKeys = Set(root.keys).subtracting(rootKeys).sorted()
    guard unknownRootKeys.isEmpty else {
      throw FinderFavoritesError.invalidConfiguration(
        "unknown top-level key(s): \(unknownRootKeys.joined(separator: ", "))"
      )
    }
    guard let entries = root["entries"] as? [Any] else { return }
    let entryKeys: Set<String> = ["id", "label", "path", "onMissing"]
    for (index, value) in entries.enumerated() {
      guard let entry = value as? [String: Any] else { continue }
      let unknownEntryKeys = Set(entry.keys).subtracting(entryKeys).sorted()
      guard unknownEntryKeys.isEmpty else {
        throw FinderFavoritesError.invalidConfiguration(
          "entries[\(index)] has unknown key(s): \(unknownEntryKeys.joined(separator: ", "))"
        )
      }
    }
  }

  private static func hasNoControlCharacters(_ value: String) -> Bool {
    value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }
}
