import FinderFavoritesCore
import Foundation

private enum SelfTestError: Error, CustomStringConvertible {
  case failed(String)

  var description: String {
    switch self {
    case .failed(let message):
      return message
    }
  }
}

@main
private enum FinderFavoritesSelfTests {
  static func main() throws {
    try withFixture { root in
      let first = root.appendingPathComponent("A")
      let second = root.appendingPathComponent("B")
      let unrelated = root.appendingPathComponent("Unrelated")
      for directory in [first, second, unrelated] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      }

      let configuration = FavoritesConfiguration(
        placement: .bottom,
        entries: [
          DesiredEntry(id: "a", label: "Project", path: first.path),
          DesiredEntry(id: "b", label: "Project", path: second.path),
        ]
      )
      let backend = InMemoryFavoritesBackend(items: [
        SidebarItem(itemID: 10, label: "A", path: first.path),
        SidebarItem(itemID: 11, label: "Unrelated", path: unrelated.path),
        SidebarItem(itemID: 12, label: "B", path: second.path),
      ])
      let engine = FavoritesEngine(
        backend: backend,
        stateDirectory: root.appendingPathComponent("state")
      )

      try engine.apply(configuration: configuration)
      try require(
        backend.items.map(\.itemID) == [11, 10, 12],
        "bottom placement did not preserve unrelated order"
      )
      try require(
        try !engine.plan(configuration: configuration).hasChanges,
        "a successful apply was not idempotent"
      )

      let missing = root.appendingPathComponent("Created")
      let createConfiguration = FavoritesConfiguration(entries: [
        DesiredEntry(
          id: "created",
          label: "Created",
          path: missing.path,
          onMissing: .createDirectory
        )
      ])
      let createBackend = InMemoryFavoritesBackend()
      let createEngine = FavoritesEngine(
        backend: createBackend,
        stateDirectory: root.appendingPathComponent("create-state")
      )
      let preview = try createEngine.apply(configuration: createConfiguration, dryRun: true)
      try require(preview.operationCount == 3, "dry-run plan omitted an expected operation")
      try require(
        !FileManager.default.fileExists(atPath: missing.path),
        "dry run created a directory"
      )
    }
    print("finder-favorites self-test passed")
  }

  private static func require(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String
  ) throws {
    guard try condition() else { throw SelfTestError.failed(message) }
  }

  private static func withFixture(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("finder-favorites-selftest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
  }
}
