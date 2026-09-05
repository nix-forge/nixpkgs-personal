import Foundation

public enum StableJSON {
  public static func data<T: Encodable>(for value: T, pretty: Bool = true) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      pretty
      ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      : [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  public static func string<T: Encodable>(for value: T, pretty: Bool = true) throws -> String {
    guard let string = String(data: try data(for: value, pretty: pretty), encoding: .utf8) else {
      throw FinderFavoritesError.backend("could not encode UTF-8 JSON output")
    }
    return string
  }
}
