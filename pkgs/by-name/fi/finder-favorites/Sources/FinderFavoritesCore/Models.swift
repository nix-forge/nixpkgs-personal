import Foundation

public enum FinderFavoritesError: Error, CustomStringConvertible, Sendable {
  case invalidConfiguration(String)
  case backend(String)
  case concurrentModification
  case verificationFailed(String)
  case unsafeInvocation(String)
  case recoveryRequired(String)

  public var description: String {
    switch self {
    case .invalidConfiguration(let message):
      return "invalid configuration: \(message)"
    case .backend(let message):
      return "Finder favorites backend: \(message)"
    case .concurrentModification:
      return "Finder favorites changed while the transaction was being prepared; retry"
    case .verificationFailed(let message):
      return "verification failed: \(message)"
    case .unsafeInvocation(let message):
      return "unsafe invocation: \(message)"
    case .recoveryRequired(let path):
      return "an unfinished transaction exists at \(path); run `finder-favorites recover`"
    }
  }
}

public enum Placement: String, Codable, CaseIterable, Sendable {
  case top
  case bottom
}

public enum MissingPathPolicy: String, Codable, CaseIterable, Sendable {
  case error
  case skip
  case createDirectory
}

public struct DesiredEntry: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let path: String
  public let onMissing: MissingPathPolicy

  public init(
    id: String,
    label: String,
    path: String,
    onMissing: MissingPathPolicy = .error
  ) {
    self.id = id
    self.label = label
    self.path = path
    self.onMissing = onMissing
  }
}

public struct FavoritesConfiguration: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let placement: Placement
  public let entries: [DesiredEntry]

  public init(
    schemaVersion: Int = 1,
    placement: Placement = .bottom,
    entries: [DesiredEntry]
  ) {
    self.schemaVersion = schemaVersion
    self.placement = placement
    self.entries = entries
  }
}

public struct SidebarItem: Codable, Equatable, Sendable {
  public let itemID: UInt32
  public let label: String
  public let path: String?

  public init(itemID: UInt32, label: String, path: String?) {
    self.itemID = itemID
    self.label = label
    self.path = path
  }
}

public struct SidebarSnapshot: Codable, Equatable, Sendable {
  public let seed: UInt32
  public let items: [SidebarItem]

  public init(seed: UInt32, items: [SidebarItem]) {
    self.seed = seed
    self.items = items
  }
}

public enum ListAnchor: Equatable, Sendable {
  case beforeFirst
  case last
  case afterItem(UInt32)
}

public struct PlanOperation: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case createDirectory
    case add
    case placeBlock
  }

  public let kind: Kind
  public let entryID: String?
  public let label: String?
  public let path: String?
  public let destination: String?

  public init(
    kind: Kind,
    entryID: String? = nil,
    label: String? = nil,
    path: String? = nil,
    destination: String? = nil
  ) {
    self.kind = kind
    self.entryID = entryID
    self.label = label
    self.path = path
    self.destination = destination
  }
}

public struct ReconciliationPlan: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let operations: [PlanOperation]
  public let warnings: [String]

  public var hasChanges: Bool { !operations.isEmpty }

  public init(
    schemaVersion: Int = 1,
    operations: [PlanOperation],
    warnings: [String]
  ) {
    self.schemaVersion = schemaVersion
    self.operations = operations
    self.warnings = warnings
  }
}

struct PreparedEntry: Equatable, Sendable {
  let desired: DesiredEntry
  let canonicalPath: String
  let exists: Bool
}

struct PreparedConfiguration: Equatable, Sendable {
  let placement: Placement
  let entries: [PreparedEntry]
  let warnings: [String]
}
