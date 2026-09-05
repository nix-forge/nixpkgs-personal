import Foundation

public enum ReconciliationPlanner {
  public static func plan(
    configuration: FavoritesConfiguration,
    snapshot: SidebarSnapshot,
    fileManager: FileManager = .default
  ) throws -> ReconciliationPlan {
    let prepared = try ConfigurationLoader.prepare(configuration, fileManager: fileManager)
    return plan(prepared: prepared, snapshot: snapshot)
  }

  static func plan(
    prepared: PreparedConfiguration,
    snapshot: SidebarSnapshot
  ) -> ReconciliationPlan {
    var warnings = prepared.warnings
    var currentByPath: [String: SidebarItem] = [:]
    for item in snapshot.items {
      guard let path = item.path else {
        warnings.append("sidebar item \(item.itemID) could not be resolved and was left untouched")
        continue
      }
      let canonical = ConfigurationLoader.canonicalPath(path)
      if currentByPath[canonical] == nil {
        currentByPath[canonical] = item
      } else {
        warnings.append("duplicate sidebar path \(canonical) was left untouched")
      }
    }

    var operations: [PlanOperation] = []
    for entry in prepared.entries where !entry.exists {
      operations.append(
        PlanOperation(
          kind: .createDirectory,
          entryID: entry.desired.id,
          label: entry.desired.label,
          path: entry.canonicalPath
        )
      )
    }

    let missing = prepared.entries.filter { currentByPath[$0.canonicalPath] == nil }
    for entry in missing {
      operations.append(
        PlanOperation(
          kind: .add,
          entryID: entry.desired.id,
          label: entry.desired.label,
          path: entry.canonicalPath,
          destination: prepared.placement.rawValue
        )
      )
    }

    let matchedIDs = prepared.entries.compactMap { currentByPath[$0.canonicalPath]?.itemID }
    if !prepared.entries.isEmpty
      && (!missing.isEmpty
        || !isCorrectlyPlaced(
          managedIDs: matchedIDs,
          allIDs: snapshot.items.map(\.itemID),
          placement: prepared.placement
        ))
    {
      operations.append(
        PlanOperation(
          kind: .placeBlock,
          label: "\(prepared.entries.count) managed item(s)",
          destination: prepared.placement.rawValue
        )
      )
    }

    return ReconciliationPlan(
      operations: operations,
      warnings: warnings
    )
  }

  static func isCorrectlyPlaced(
    managedIDs: [UInt32],
    allIDs: [UInt32],
    placement: Placement
  ) -> Bool {
    guard !managedIDs.isEmpty else { return true }
    let managedSet = Set(managedIDs)
    let actualManaged = allIDs.filter { managedSet.contains($0) }
    guard actualManaged == managedIDs else { return false }
    switch placement {
    case .top:
      return Array(allIDs.prefix(managedIDs.count)) == managedIDs
    case .bottom:
      return Array(allIDs.suffix(managedIDs.count)) == managedIDs
    }
  }
}
