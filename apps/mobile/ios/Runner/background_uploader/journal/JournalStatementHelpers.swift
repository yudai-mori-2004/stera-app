import Foundation
import SQLite3

// ─────────────────────────────────────────────────────────────────────────────
// Low-level bind/read helpers shared by the journal's database core and its
// table stores, so every component reads and writes columns the same way.
// Mixed in via an empty marker protocol rather than free functions to keep the
// call sites unprefixed (`bindText(stmt, …)`) and out of the module namespace.
// ─────────────────────────────────────────────────────────────────────────────

/// sqlite3 wants SQLITE_TRANSIENT so it copies bound text rather than aliasing
/// a Swift buffer that may be freed before the statement runs.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

protocol JournalStatementBinding {}

extension JournalStatementBinding {
    func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    func bindTextOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, index) }
    }

    func bindDateOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: Date?) {
        if let v = value { sqlite3_bind_int64(stmt, index, Int64(v.timeIntervalSince1970)) }
        else { sqlite3_bind_null(stmt, index) }
    }

    func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}
