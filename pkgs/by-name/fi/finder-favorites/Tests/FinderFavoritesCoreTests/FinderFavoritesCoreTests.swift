import Darwin
import Foundation
import XCTest

@testable import FinderFavoritesCore

final class FinderFavoritesCoreTests: XCTestCase {
  func testApplyHoldsProcessLockDuringSidebarWrites() throws {
    try withTemporaryDirectories(["A"]) { root in
      let state = root.appendingPathComponent("state")
      let backend = LockProbingBackend(lockURL: state.appendingPathComponent("lock"))
      let engine = FavoritesEngine(backend: backend, stateDirectory: state)
      try engine.apply(
        configuration: FavoritesConfiguration(entries: [
          entry("a", root.appendingPathComponent("A"))
        ])
      )
      XCTAssertTrue(backend.lockWasHeld)
    }
  }

  func testBottomPlacementIsStableAndIdempotent() throws {
    try withTemporaryDirectories(["A", "B", "Other"]) { root in
      let configuration = FavoritesConfiguration(
        placement: .bottom,
        entries: [
          entry("a", root.appendingPathComponent("A")),
          entry("b", root.appendingPathComponent("B")),
        ]
      )
      let backend = InMemoryFavoritesBackend(items: [
        item(10, "A", root.appendingPathComponent("A")),
        item(11, "Other", root.appendingPathComponent("Other")),
        item(12, "B", root.appendingPathComponent("B")),
      ])
      let engine = FavoritesEngine(
        backend: backend,
        stateDirectory: root.appendingPathComponent("state")
      )

      let result = try engine.apply(configuration: configuration)
      XCTAssertTrue(result.changed)
      XCTAssertEqual(backend.items.map(\.itemID), [11, 10, 12])
      XCTAssertFalse(try engine.plan(configuration: configuration).hasChanges)
    }
  }

  func testTopPlacementPreservesUnrelatedItemOrder() throws {
    try withTemporaryDirectories(["A", "B", "X", "Y"]) { root in
      let configuration = FavoritesConfiguration(
        placement: .top,
        entries: [
          entry("a", root.appendingPathComponent("A")),
          entry("b", root.appendingPathComponent("B")),
        ]
      )
      let backend = InMemoryFavoritesBackend(items: [
        item(20, "X", root.appendingPathComponent("X")),
        item(21, "B", root.appendingPathComponent("B")),
        item(22, "Y", root.appendingPathComponent("Y")),
        item(23, "A", root.appendingPathComponent("A")),
      ])
      let engine = FavoritesEngine(
        backend: backend,
        stateDirectory: root.appendingPathComponent("state")
      )

      try engine.apply(configuration: configuration)
      XCTAssertEqual(backend.items.map(\.itemID), [23, 21, 20, 22])
    }
  }

  func testMissingDirectoriesAreCreatedOnlyWhenRequested() throws {
    try withTemporaryDirectories([]) { root in
      let directory = root.appendingPathComponent("Created")
      let configuration = FavoritesConfiguration(entries: [
        DesiredEntry(
          id: "created",
          label: "Created",
          path: directory.path,
          onMissing: .createDirectory
        )
      ])
      let backend = InMemoryFavoritesBackend()
      let engine = FavoritesEngine(
        backend: backend,
        stateDirectory: root.appendingPathComponent("state")
      )

      let preview = try engine.apply(configuration: configuration, dryRun: true)
      XCTAssertEqual(preview.operationCount, 3)
      XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
      try engine.apply(configuration: configuration)
      XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
      XCTAssertEqual(backend.items.first?.path, directory.path)
    }
  }

  func testLabelsMayRepeatBecauseIdentityIsPathBased() throws {
    try withTemporaryDirectories(["A", "B"]) { root in
      let configuration = FavoritesConfiguration(entries: [
        DesiredEntry(id: "a", label: "Project", path: root.appendingPathComponent("A").path),
        DesiredEntry(id: "b", label: "Project", path: root.appendingPathComponent("B").path),
      ])
      try ConfigurationLoader.validate(configuration)
    }
  }

  func testDuplicateCanonicalPathsAreRejected() throws {
    try withTemporaryDirectories(["A"]) { root in
      let path = root.appendingPathComponent("A").path
      let configuration = FavoritesConfiguration(entries: [
        DesiredEntry(id: "a", label: "A", path: path),
        DesiredEntry(id: "b", label: "B", path: path + "/."),
      ])
      XCTAssertThrowsError(try ConfigurationLoader.validate(configuration))
    }
  }

  func testUnknownConfigurationKeysAreRejected() throws {
    try withTemporaryDirectories([]) { root in
      let configURL = root.appendingPathComponent("config.json")
      let data = Data(
        """
        {"schemaVersion":1,"placement":"bottom","entries":[],"typo":true}
        """.utf8
      )
      try data.write(to: configURL)
      XCTAssertThrowsError(try ConfigurationLoader.load(from: configURL))
    }
  }

  func testConcurrentSidebarChangeAbortsBeforeWriting() throws {
    try withTemporaryDirectories(["A", "Other", "External"]) { root in
      let initial = [
        item(40, "Other", root.appendingPathComponent("Other")),
        item(41, "A", root.appendingPathComponent("A")),
      ]
      let changed =
        initial + [
          item(42, "External", root.appendingPathComponent("External"))
        ]
      let backend = SnapshotSequenceBackend(snapshots: [initial, initial, changed])
      let engine = FavoritesEngine(
        backend: backend,
        stateDirectory: root.appendingPathComponent("state")
      )
      let configuration = FavoritesConfiguration(
        placement: .top,
        entries: [entry("a", root.appendingPathComponent("A"))]
      )

      XCTAssertThrowsError(try engine.apply(configuration: configuration))
      XCTAssertFalse(backend.didMutate)
    }
  }

  func testFailedWriteRollsBackInsertedRowsAndOriginalOrder() throws {
    try withTemporaryDirectories(["A", "B", "Other"]) { root in
      let memory = InMemoryFavoritesBackend(items: [
        item(30, "Other", root.appendingPathComponent("Other")),
        item(31, "A", root.appendingPathComponent("A")),
      ])
      let backend = FailOneMoveBackend(wrapping: memory)
      let engine = FavoritesEngine(
        backend: backend,
        stateDirectory: root.appendingPathComponent("state")
      )
      let configuration = FavoritesConfiguration(
        placement: .top,
        entries: [
          entry("a", root.appendingPathComponent("A")),
          entry("b", root.appendingPathComponent("B")),
        ])

      XCTAssertThrowsError(try engine.apply(configuration: configuration))
      XCTAssertEqual(memory.items.map(\.itemID), [30, 31])
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: root.appendingPathComponent("state/transaction.json").path
        )
      )
    }
  }

  private func entry(_ id: String, _ url: URL) -> DesiredEntry {
    DesiredEntry(id: id, label: url.lastPathComponent, path: url.path)
  }

  private func item(_ id: UInt32, _ label: String, _ url: URL) -> SidebarItem {
    SidebarItem(itemID: id, label: label, path: url.path)
  }

  private func withTemporaryDirectories(
    _ names: [String],
    body: (URL) throws -> Void
  ) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("finder-favorites-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in names {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(name),
        withIntermediateDirectories: false
      )
    }
    try body(root)
  }
}

private final class LockProbingBackend: FavoritesBackend {
  private let wrapped = InMemoryFavoritesBackend()
  private let lockURL: URL
  private(set) var lockWasHeld = false

  init(lockURL: URL) {
    self.lockURL = lockURL
  }

  func snapshot() throws -> SidebarSnapshot { try wrapped.snapshot() }

  func insert(label: String, path: String, at anchor: ListAnchor) throws -> UInt32 {
    let descriptor = open(lockURL.path, O_RDWR)
    guard descriptor >= 0 else { throw FinderFavoritesError.backend("test lock file is missing") }
    defer { close(descriptor) }
    lockWasHeld = flock(descriptor, LOCK_EX | LOCK_NB) != 0 && errno == EWOULDBLOCK
    return try wrapped.insert(label: label, path: path, at: anchor)
  }

  func move(itemID: UInt32, to anchor: ListAnchor) throws {
    try wrapped.move(itemID: itemID, to: anchor)
  }

  func remove(itemID: UInt32) throws {
    try wrapped.remove(itemID: itemID)
  }
}

private final class FailOneMoveBackend: FavoritesBackend {
  private let wrapped: InMemoryFavoritesBackend
  private var shouldFail = true

  init(wrapping wrapped: InMemoryFavoritesBackend) {
    self.wrapped = wrapped
  }

  func snapshot() throws -> SidebarSnapshot { try wrapped.snapshot() }

  func insert(label: String, path: String, at anchor: ListAnchor) throws -> UInt32 {
    try wrapped.insert(label: label, path: path, at: anchor)
  }

  func move(itemID: UInt32, to anchor: ListAnchor) throws {
    if shouldFail {
      shouldFail = false
      throw FinderFavoritesError.backend("injected move failure")
    }
    try wrapped.move(itemID: itemID, to: anchor)
  }

  func remove(itemID: UInt32) throws {
    try wrapped.remove(itemID: itemID)
  }
}

private final class SnapshotSequenceBackend: FavoritesBackend {
  private let snapshots: [[SidebarItem]]
  private var index = 0
  private(set) var didMutate = false

  init(snapshots: [[SidebarItem]]) {
    self.snapshots = snapshots
  }

  func snapshot() throws -> SidebarSnapshot {
    let items = snapshots[min(index, snapshots.count - 1)]
    index += 1
    return SidebarSnapshot(seed: UInt32(index), items: items)
  }

  func insert(label _: String, path _: String, at _: ListAnchor) throws -> UInt32 {
    didMutate = true
    return 999
  }

  func move(itemID _: UInt32, to _: ListAnchor) throws {
    didMutate = true
  }

  func remove(itemID _: UInt32) throws {
    didMutate = true
  }
}
