import AppKit
import SwiftUI
import SQLite3

guard sqlite3_libversion_number() == SQLITE_VERSION_NUMBER else {
    fatalError("SQLite runtime does not match the imported headers")
}

var database: OpaquePointer?
guard sqlite3_open(":memory:", &database) == SQLITE_OK else {
    fatalError("Cannot open in-memory SQLite database")
}
defer { sqlite3_close(database) }

var statement: OpaquePointer?
guard sqlite3_prepare_v2(database, "SELECT 42", -1, &statement, nil) == SQLITE_OK else {
    fatalError("Cannot prepare SQLite query")
}
defer { sqlite3_finalize(statement) }

guard sqlite3_step(statement) == SQLITE_ROW,
      sqlite3_column_int(statement, 0) == 42 else {
    fatalError("SQLite query returned an unexpected result")
}
print("SQLite3 import, link, and query passed.")
