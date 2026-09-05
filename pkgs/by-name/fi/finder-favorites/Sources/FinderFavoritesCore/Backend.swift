import Darwin
import FinderFavoritesBridge
import Foundation

public enum ProcessArguments {
  public static var current: [String] {
    (0..<ff_bridge_argument_count()).compactMap { index in
      ff_bridge_argument_at(index).map(String.init(cString:))
    }
  }
}

public protocol FavoritesBackend: AnyObject {
  func snapshot() throws -> SidebarSnapshot
  func insert(label: String, path: String, at anchor: ListAnchor) throws -> UInt32
  func move(itemID: UInt32, to anchor: ListAnchor) throws
  func remove(itemID: UInt32) throws
}

public final class LegacySharedFileListBackend: FavoritesBackend {
  public init() {}

  public func snapshot() throws -> SidebarSnapshot {
    var errorPointer: UnsafeMutablePointer<CChar>?
    guard let bridgeSnapshot = ff_bridge_copy_snapshot(&errorPointer) else {
      throw bridgeError(errorPointer)
    }
    defer { ff_bridge_free_snapshot(bridgeSnapshot) }

    let count = ff_bridge_snapshot_count(bridgeSnapshot)
    var items: [SidebarItem] = []
    items.reserveCapacity(count)
    for index in 0..<count {
      var itemID: UInt32 = 0
      var namePointer: UnsafePointer<CChar>?
      var pathPointer: UnsafePointer<CChar>?
      var resolved = false
      guard
        ff_bridge_snapshot_item(
          bridgeSnapshot,
          index,
          &itemID,
          &namePointer,
          &pathPointer,
          &resolved
        )
      else {
        throw FinderFavoritesError.backend("the native bridge returned an invalid item")
      }
      let label = namePointer.map(String.init(cString:)) ?? ""
      let path = resolved ? pathPointer.map(String.init(cString:)) : nil
      items.append(SidebarItem(itemID: itemID, label: label, path: path))
    }
    return SidebarSnapshot(seed: ff_bridge_snapshot_seed(bridgeSnapshot), items: items)
  }

  public func insert(label: String, path: String, at anchor: ListAnchor) throws -> UInt32 {
    let position = bridgePosition(anchor)
    var insertedID: UInt32 = 0
    var errorPointer: UnsafeMutablePointer<CChar>?
    let status = label.withCString { labelPointer in
      path.withCString { pathPointer in
        ff_bridge_insert(
          labelPointer,
          pathPointer,
          position.kind,
          position.afterID,
          &insertedID,
          &errorPointer
        )
      }
    }
    guard status == 0 else { throw bridgeError(errorPointer) }
    return insertedID
  }

  public func move(itemID: UInt32, to anchor: ListAnchor) throws {
    let position = bridgePosition(anchor)
    var errorPointer: UnsafeMutablePointer<CChar>?
    let status = ff_bridge_move(
      itemID,
      position.kind,
      position.afterID,
      &errorPointer
    )
    guard status == 0 else { throw bridgeError(errorPointer) }
  }

  public func remove(itemID: UInt32) throws {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let status = ff_bridge_remove(itemID, &errorPointer)
    guard status == 0 else { throw bridgeError(errorPointer) }
  }

  private func bridgePosition(
    _ anchor: ListAnchor
  ) -> (kind: FFBridgePosition, afterID: UInt32) {
    switch anchor {
    case .beforeFirst:
      return (FFBridgePositionBeforeFirst, 0)
    case .last:
      return (FFBridgePositionLast, 0)
    case .afterItem(let itemID):
      return (FFBridgePositionAfterItem, itemID)
    }
  }

  private func bridgeError(
    _ pointer: UnsafeMutablePointer<CChar>?
  ) -> FinderFavoritesError {
    guard let pointer else {
      return .backend("an unknown native bridge error occurred")
    }
    let message = String(cString: pointer)
    ff_bridge_free_error(pointer)
    return .backend(message)
  }
}

public final class InMemoryFavoritesBackend: FavoritesBackend {
  public private(set) var items: [SidebarItem]
  private var seed: UInt32
  private var nextID: UInt32

  public init(items: [SidebarItem] = [], seed: UInt32 = 1) {
    self.items = items
    self.seed = seed
    self.nextID = (items.map(\.itemID).max() ?? 0) + 1
  }

  public func snapshot() throws -> SidebarSnapshot {
    SidebarSnapshot(seed: seed, items: items)
  }

  public func insert(label: String, path: String, at anchor: ListAnchor) throws -> UInt32 {
    let item = SidebarItem(itemID: nextID, label: label, path: path)
    nextID += 1
    insert(item, at: anchor)
    seed += 1
    return item.itemID
  }

  public func move(itemID: UInt32, to anchor: ListAnchor) throws {
    guard let index = items.firstIndex(where: { $0.itemID == itemID }) else {
      throw FinderFavoritesError.backend("item \(itemID) does not exist")
    }
    let item = items.remove(at: index)
    insert(item, at: anchor)
    seed += 1
  }

  public func remove(itemID: UInt32) throws {
    items.removeAll { $0.itemID == itemID }
    seed += 1
  }

  private func insert(_ item: SidebarItem, at anchor: ListAnchor) {
    switch anchor {
    case .beforeFirst:
      items.insert(item, at: 0)
    case .last:
      items.append(item)
    case .afterItem(let itemID):
      let index = items.firstIndex(where: { $0.itemID == itemID }) ?? (items.count - 1)
      items.insert(item, at: min(index + 1, items.count))
    }
  }
}
