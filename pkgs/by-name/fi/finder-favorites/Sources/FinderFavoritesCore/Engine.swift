import Darwin
import Foundation

public struct ApplyResult: Codable, Equatable, Sendable {
  public let changed: Bool
  public let dryRun: Bool
  public let operationCount: Int
  public let warnings: [String]

  public init(changed: Bool, dryRun: Bool, operationCount: Int, warnings: [String]) {
    self.changed = changed
    self.dryRun = dryRun
    self.operationCount = operationCount
    self.warnings = warnings
  }
}

private struct TransactionJournal: Codable {
  let schemaVersion: Int
  let originalOrder: [UInt32]
  let managedPaths: [String]
  var insertedItemIDs: [UInt32]
  var createdDirectories: [String]
}

public final class FavoritesEngine {
  private let backend: FavoritesBackend
  private let stateDirectory: URL
  private let fileManager: FileManager

  public init(
    backend: FavoritesBackend,
    stateDirectory: URL,
    fileManager: FileManager = .default
  ) {
    self.backend = backend
    self.stateDirectory = stateDirectory
    self.fileManager = fileManager
  }

  public func list() throws -> SidebarSnapshot {
    try backend.snapshot()
  }

  public func plan(configuration: FavoritesConfiguration) throws -> ReconciliationPlan {
    try ReconciliationPlanner.plan(
      configuration: configuration,
      snapshot: backend.snapshot(),
      fileManager: fileManager
    )
  }

  @discardableResult
  public func apply(
    configuration: FavoritesConfiguration,
    dryRun: Bool = false
  ) throws -> ApplyResult {
    let preview = try plan(configuration: configuration)
    if dryRun || !preview.hasChanges {
      return ApplyResult(
        changed: preview.hasChanges,
        dryRun: dryRun,
        operationCount: preview.operations.count,
        warnings: preview.warnings
      )
    }
    try rejectPrivilegedInvocation()
    try prepareStateDirectory()
    let lock = try ProcessLock(url: stateDirectory.appendingPathComponent("lock"))
    _ = lock

    let journalURL = stateDirectory.appendingPathComponent("transaction.json")
    if fileManager.fileExists(atPath: journalURL.path) {
      throw FinderFavoritesError.recoveryRequired(journalURL.path)
    }

    let prepared = try ConfigurationLoader.prepare(configuration, fileManager: fileManager)
    let original = try backend.snapshot()
    let lockedPlan = ReconciliationPlanner.plan(prepared: prepared, snapshot: original)
    guard lockedPlan.hasChanges else {
      return ApplyResult(
        changed: false,
        dryRun: false,
        operationCount: 0,
        warnings: lockedPlan.warnings
      )
    }

    var journal = TransactionJournal(
      schemaVersion: 1,
      originalOrder: original.items.map(\.itemID),
      managedPaths: prepared.entries.map(\.canonicalPath),
      insertedItemIDs: [],
      createdDirectories: []
    )
    try writeJournal(journal, to: journalURL)

    let confirmation: SidebarSnapshot
    do {
      confirmation = try backend.snapshot()
    } catch {
      try fileManager.removeItem(at: journalURL)
      throw error
    }
    // macOS 26 returns a different LSSharedFileList seed on every snapshot,
    // even without a list change. Compare the ordered resolved content.
    guard confirmation.items == original.items else {
      try fileManager.removeItem(at: journalURL)
      throw FinderFavoritesError.concurrentModification
    }

    do {
      for entry in prepared.entries where !entry.exists {
        try fileManager.createDirectory(
          atPath: entry.canonicalPath,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
        journal.createdDirectories.append(entry.canonicalPath)
        try writeJournal(journal, to: journalURL)
      }

      var current = try backend.snapshot()
      var itemsByPath = resolvedItemsByPath(current)
      for entry in prepared.entries where itemsByPath[entry.canonicalPath] == nil {
        let insertedID = try backend.insert(
          label: entry.desired.label,
          path: entry.canonicalPath,
          at: .last
        )
        journal.insertedItemIDs.append(insertedID)
        try writeJournal(journal, to: journalURL)
        current = try backend.snapshot()
        itemsByPath = resolvedItemsByPath(current)
      }

      try placeManagedBlock(prepared: prepared, snapshot: current)
      let verification = ReconciliationPlanner.plan(
        prepared: try ConfigurationLoader.prepare(configuration, fileManager: fileManager),
        snapshot: try backend.snapshot()
      )
      guard !verification.hasChanges else {
        throw FinderFavoritesError.verificationFailed(
          "\(verification.operations.count) operation(s) remain after apply"
        )
      }
      try fileManager.removeItem(at: journalURL)
      return ApplyResult(
        changed: true,
        dryRun: false,
        operationCount: lockedPlan.operations.count,
        warnings: verification.warnings
      )
    } catch {
      do {
        try rollback(journal: journal)
        if fileManager.fileExists(atPath: journalURL.path) {
          try fileManager.removeItem(at: journalURL)
        }
      } catch let rollbackError {
        throw FinderFavoritesError.recoveryRequired(
          "\(journalURL.path) (original error: \(error); rollback error: \(rollbackError))"
        )
      }
      throw error
    }
  }

  public func recover() throws {
    try rejectPrivilegedInvocation()
    try prepareStateDirectory()
    let lock = try ProcessLock(url: stateDirectory.appendingPathComponent("lock"))
    _ = lock
    let journalURL = stateDirectory.appendingPathComponent("transaction.json")
    guard fileManager.fileExists(atPath: journalURL.path) else { return }
    let data = try Data(contentsOf: journalURL)
    let journal = try JSONDecoder().decode(TransactionJournal.self, from: data)
    guard journal.schemaVersion == 1 else {
      throw FinderFavoritesError.recoveryRequired(
        "\(journalURL.path) uses an unsupported journal schema"
      )
    }
    try rollback(journal: journal)
    try fileManager.removeItem(at: journalURL)
  }

  public func exportConfiguration() throws -> FavoritesConfiguration {
    let entries = try backend.snapshot().items.compactMap { item -> DesiredEntry? in
      guard let path = item.path else { return nil }
      return DesiredEntry(
        id: "item-\(item.itemID)",
        label: item.label.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : item.label,
        path: path,
        onMissing: .error
      )
    }
    return FavoritesConfiguration(placement: .bottom, entries: entries)
  }

  private func placeManagedBlock(
    prepared: PreparedConfiguration,
    snapshot: SidebarSnapshot
  ) throws {
    let itemsByPath = resolvedItemsByPath(snapshot)
    let managedIDs = prepared.entries.compactMap { itemsByPath[$0.canonicalPath]?.itemID }
    guard managedIDs.count == prepared.entries.count else {
      throw FinderFavoritesError.verificationFailed(
        "one or more inserted paths did not appear in the Finder favorites snapshot"
      )
    }
    guard
      !ReconciliationPlanner.isCorrectlyPlaced(
        managedIDs: managedIDs,
        allIDs: snapshot.items.map(\.itemID),
        placement: prepared.placement
      )
    else { return }

    switch prepared.placement {
    case .top:
      for itemID in managedIDs.reversed() {
        try backend.move(itemID: itemID, to: .beforeFirst)
      }
    case .bottom:
      for itemID in managedIDs {
        try backend.move(itemID: itemID, to: .last)
      }
    }
  }

  private func rollback(journal: TransactionJournal) throws {
    let originalIDs = Set(journal.originalOrder)
    let managedPaths = Set(journal.managedPaths)
    let snapshot = try backend.snapshot()
    for item in snapshot.items {
      let canonical = item.path.map(ConfigurationLoader.canonicalPath)
      let wasInserted =
        journal.insertedItemIDs.contains(item.itemID)
        || (canonical.map(managedPaths.contains) == true && !originalIDs.contains(item.itemID))
      if wasInserted {
        try backend.remove(itemID: item.itemID)
      }
    }

    let remainingIDs = Set(try backend.snapshot().items.map(\.itemID))
    for itemID in journal.originalOrder where remainingIDs.contains(itemID) {
      try backend.move(itemID: itemID, to: .last)
    }

    for directory in journal.createdDirectories.reversed() {
      if fileManager.fileExists(atPath: directory),
        try fileManager.contentsOfDirectory(atPath: directory).isEmpty
      {
        try fileManager.removeItem(atPath: directory)
      }
    }
  }

  private func resolvedItemsByPath(_ snapshot: SidebarSnapshot) -> [String: SidebarItem] {
    var result: [String: SidebarItem] = [:]
    for item in snapshot.items {
      guard let path = item.path else { continue }
      let canonical = ConfigurationLoader.canonicalPath(path)
      if result[canonical] == nil {
        result[canonical] = item
      }
    }
    return result
  }

  private func prepareStateDirectory() throws {
    try fileManager.createDirectory(
      at: stateDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateDirectory.path)
  }

  private func writeJournal(_ journal: TransactionJournal, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(journal)
    try data.write(to: url, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func rejectPrivilegedInvocation() throws {
    guard getuid() != 0 && geteuid() != 0 else {
      throw FinderFavoritesError.unsafeInvocation(
        "do not run this per-user tool as root or through sudo"
      )
    }
  }
}

private final class ProcessLock {
  private let descriptor: Int32

  init(url: URL) throws {
    descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw FinderFavoritesError.backend(
        "could not open lock file \(url.path): \(String(cString: strerror(errno)))"
      )
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let message = String(cString: strerror(errno))
      close(descriptor)
      throw FinderFavoritesError.backend("another apply is running: \(message)")
    }
  }

  deinit {
    _ = flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
