import Foundation
import SQLite3

// ─────────────────────────────────────────────────────────────────────────────
// Store for the `sessions` table — session config, lifecycle state, and the
// one-shot notification flags. Shares the database core's serial queue, so its
// ops interleave safely with PartStore's.
// ─────────────────────────────────────────────────────────────────────────────

final class SessionStore: JournalStatementBinding {
    private let db: JournalDatabase

    init(db: JournalDatabase) {
        self.db = db
    }

    func upsertSession(
        sessionId: String, fileUrl: String, chunkSize: Int, fileSize: Int64,
        contentType: String, windowSize: Int, state: String
    ) {
        db.sync { handle in
            let sql = """
            INSERT INTO sessions (session_id, file_url, chunk_size, file_size, content_type, window_size, state)
            VALUES (?,?,?,?,?,?,?)
            ON CONFLICT(session_id) DO UPDATE SET state=excluded.state, window_size=excluded.window_size;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, sessionId)
            bindText(stmt, 2, fileUrl)
            sqlite3_bind_int64(stmt, 3, Int64(chunkSize))
            sqlite3_bind_int64(stmt, 4, fileSize)
            bindText(stmt, 5, contentType)
            sqlite3_bind_int64(stmt, 6, Int64(windowSize))
            bindText(stmt, 7, state)
            sqlite3_step(stmt)
        }
    }

    func setSessionState(_ sessionId: String, _ state: String) {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "UPDATE sessions SET state=? WHERE session_id=?", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, state)
            bindText(stmt, 2, sessionId)
            sqlite3_step(stmt)
        }
    }

    func sessionState(_ sessionId: String) -> String? {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT state FROM sessions WHERE session_id=?", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, sessionId)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return columnText(stmt, 0)
        }
    }

    func totalParts(for sessionId: String) -> Int {
        guard let cfg = sessionConfig(sessionId), cfg.chunkSize > 0 else { return 0 }
        return Int((cfg.fileSize + Int64(cfg.chunkSize) - 1) / Int64(cfg.chunkSize))
    }

    // MARK: - Notification flags

    func stallNotificationSent(_ sessionId: String) -> Bool {
        sentFlag("stall_notification_sent_at", sessionId)
    }

    func finishNotificationSent(_ sessionId: String) -> Bool {
        sentFlag("finish_notification_sent_at", sessionId)
    }

    func markStallNotificationSent(_ sessionId: String) {
        markSent("stall_notification_sent_at", sessionId)
    }

    func markFinishNotificationSent(_ sessionId: String) {
        markSent("finish_notification_sent_at", sessionId)
    }

    /// Highest 10%% progress bucket already announced in a background
    /// notification for this session (0 = none yet).
    func progressNotifiedBucket(_ sessionId: String) -> Int {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(
                handle,
                "SELECT progress_notified_bucket FROM sessions WHERE session_id=?",
                -1, &stmt, nil
            ) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, sessionId)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    func setProgressNotifiedBucket(_ sessionId: String, _ bucket: Int) {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(
                handle,
                "UPDATE sessions SET progress_notified_bucket=? WHERE session_id=?",
                -1, &stmt, nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(bucket))
            bindText(stmt, 2, sessionId)
            sqlite3_step(stmt)
        }
    }

    /// Batch counts for the progress notification's "X/Y" — completed videos
    /// (`drained`, all parts uploaded) over the total still in play (anything
    /// not cancelled). Mirrors the Dart UI's "completed/total" tally without
    /// Dart having to feed the numbers in: the journal already holds one row per
    /// in-flight session, so this stays accurate while Dart is dead.
    func videoCounts() -> (completed: Int, total: Int) {
        db.sync { handle in
            (
                completed: count(handle, "SELECT COUNT(*) FROM sessions WHERE state='drained'"),
                total: count(handle, "SELECT COUNT(*) FROM sessions WHERE state!='cancelled'")
            )
        }
    }

    private func count(_ handle: OpaquePointer?, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    func clearStallNotificationSent(_ sessionId: String) {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(
                handle,
                "UPDATE sessions SET stall_notification_sent_at=NULL WHERE session_id=?",
                -1, &stmt, nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, sessionId)
            sqlite3_step(stmt)
        }
    }

    private func sentFlag(_ column: String, _ sessionId: String) -> Bool {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(
                handle,
                "SELECT \(column) FROM sessions WHERE session_id=?",
                -1, &stmt, nil
            ) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, sessionId)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
            return sqlite3_column_int64(stmt, 0) > 0
        }
    }

    private func markSent(_ column: String, _ sessionId: String) {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(
                handle,
                "UPDATE sessions SET \(column)=? WHERE session_id=?",
                -1, &stmt, nil
            ) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
            bindText(stmt, 2, sessionId)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Reads

    func sessionConfig(_ sessionId: String) -> JournalSession? {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT session_id, file_url, chunk_size, file_size, content_type, window_size, state FROM sessions WHERE session_id=?", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, sessionId)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return JournalSession(
                sessionId: columnText(stmt, 0) ?? "",
                fileUrl: columnText(stmt, 1) ?? "",
                chunkSize: Int(sqlite3_column_int64(stmt, 2)),
                fileSize: sqlite3_column_int64(stmt, 3),
                contentType: columnText(stmt, 4) ?? "",
                windowSize: Int(sqlite3_column_int64(stmt, 5)),
                state: columnText(stmt, 6) ?? ""
            )
        }
    }

    func activeSessionIds() -> [String] {
        sessionIds("SELECT session_id FROM sessions WHERE state='active'")
    }

    /// Every session regardless of state — used by the launch reconcile to find
    /// done/aborted sessions whose zombie tasks should be cancelled.
    func allSessionIds() -> [String] {
        sessionIds("SELECT session_id FROM sessions")
    }

    private func sessionIds(_ sql: String) -> [String] {
        db.sync { handle in
            var ids: [String] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return ids }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW { ids.append(columnText(stmt, 0) ?? "") }
            return ids
        }
    }

    /// Tear down a session and all its parts. Cascades to the `parts` table here
    /// (SQLite has no FK cascade configured) in one queued transaction so a reader
    /// never observes a session whose parts were half-deleted.
    func deleteSession(_ sessionId: String) {
        db.sync { handle in
            for table in ["parts", "sessions"] {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(handle, "DELETE FROM \(table) WHERE session_id=?", -1, &stmt, nil) == SQLITE_OK {
                    bindText(stmt, 1, sessionId)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }
    }
}
