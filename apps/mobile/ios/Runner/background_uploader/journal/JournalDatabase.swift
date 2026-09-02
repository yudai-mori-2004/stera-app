import Foundation
import SQLite3

// ─────────────────────────────────────────────────────────────────────────────
// SQLite core for the native transfer journal — owns the connection, the serial
// queue every journal op runs on, and the schema + column migrations. The table
// stores (SessionStore, PartStore) share ONE instance, so all reads/writes
// serialize through `sync` and the atomic `BEGIN IMMEDIATE` claim is safe from
// the URLSession delegate queue.
// ─────────────────────────────────────────────────────────────────────────────

final class JournalDatabase: JournalStatementBinding {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "io.rootlens.app.uploadJournal")

    init(path: URL? = nil) {
        let url = path ?? JournalDatabase.defaultPath()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("⚠️ UploadJournal: failed to open \(url.path)")
        }
        exec("PRAGMA journal_mode=WAL;")
        createTables()
    }

    deinit { if db != nil { sqlite3_close(db) } }

    /// Run [body] on the serial queue with the raw connection handle. Every store
    /// op funnels through here, so they never race the connection and the claim
    /// transaction stays atomic.
    @discardableResult
    func sync<T>(_ body: (OpaquePointer?) -> T) -> T {
        queue.sync { body(db) }
    }

    /// Fire-and-forget SQL against the owned connection. On-queue only (caller
    /// already holds `sync`, or it's `init`) — do not call off-queue.
    func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// Single-COUNT(*) query; caller binds parameters via [bind]. On-queue only.
    func intCount(_ sql: String, bind: (OpaquePointer?) -> Void) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    // MARK: - Schema

    private static func defaultPath() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support.appendingPathComponent("upload_journal.sqlite")
    }

    private func createTables() {
        exec("""
        CREATE TABLE IF NOT EXISTS sessions (
          session_id TEXT PRIMARY KEY,
          file_url TEXT NOT NULL,
          chunk_size INTEGER NOT NULL,
          file_size INTEGER NOT NULL,
          content_type TEXT NOT NULL,
          window_size INTEGER NOT NULL,
          state TEXT NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS parts (
          session_id TEXT NOT NULL,
          part_number INTEGER NOT NULL,
          offset INTEGER NOT NULL,
          length INTEGER NOT NULL,
          url TEXT,
          url_expires_at INTEGER,
          state TEXT NOT NULL,
          task_id INTEGER,
          temp_path TEXT,
          etag TEXT,
          md5 TEXT,
          attempts INTEGER NOT NULL DEFAULT 0,
          error_code TEXT,
          PRIMARY KEY (session_id, part_number)
        );
        """)
        migrateColumns()
    }

    private func migrateColumns() {
        addColumnIfMissing("sessions", "stall_notification_sent_at", "INTEGER")
        addColumnIfMissing("sessions", "finish_notification_sent_at", "INTEGER")
        // Highest 10%% progress bucket already surfaced in a background
        // notification (0 = none). Lets the engine fire the progress
        // notification once per crossed bucket instead of on every part.
        addColumnIfMissing("sessions", "progress_notified_bucket", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("parts", "drain_acknowledged", "INTEGER NOT NULL DEFAULT 0")
    }

    private func addColumnIfMissing(_ table: String, _ column: String, _ type: String) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if columnText(stmt, 1) == column { return }
            }
            exec("ALTER TABLE \(table) ADD COLUMN \(column) \(type);")
        }
    }
}
