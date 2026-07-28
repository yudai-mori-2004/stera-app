import Foundation
import SQLite3

// ─────────────────────────────────────────────────────────────────────────────
// Store for the `parts` table — the transfer window's per-part state, the
// atomic claim/reclaim transitions, counts, and the drain/ack handshake. Shares
// the database core's serial queue with SessionStore.
// ─────────────────────────────────────────────────────────────────────────────

final class PartStore: JournalStatementBinding {
    private let db: JournalDatabase

    init(db: JournalDatabase) {
        self.db = db
    }

    /// Insert manifest parts, or refresh existing rows from a re-pushed manifest
    /// (`beginSession` on retry/resume, `provideUrls` mid-transfer).
    ///
    /// On conflict the row adopts the incoming transfer state, not just the URL.
    /// The manifest is Dart's declaration that these parts still need
    /// transferring, and this upsert is the ONLY transition that returns a part
    /// to `planned` from the two dead-end states: `error` (HTTP-rejected part,
    /// parked pending Dart's retry decision — see ChunkWindowManager
    /// `didCompleteWithError`) and stale `uploaded` (parts sent to a multipart
    /// upload that has since been replaced on restart). `claimNextSchedulablePart`
    /// only picks `planned`, so without this a retried session resumes, reaches
    /// the parked part, and wedges into `needUrlsStall` forever.
    ///
    /// `inFlight` rows keep their transfer state/bookkeeping — their URLSession
    /// task is live, and demoting them to `planned` would double-schedule the
    /// part — but still take the fresh URL for the retry that follows if that
    /// task fails.
    func upsertParts(_ parts: [JournalPart]) {
        db.sync { handle in
            db.exec("BEGIN;")
            for p in parts {
                let sql = """
                INSERT INTO parts (session_id, part_number, offset, length, url, url_expires_at, state, attempts)
                VALUES (?,?,?,?,?,?,?,?)
                ON CONFLICT(session_id, part_number) DO UPDATE SET
                  url=excluded.url,
                  url_expires_at=excluded.url_expires_at,
                  state=CASE WHEN parts.state='inFlight' THEN parts.state ELSE excluded.state END,
                  attempts=CASE WHEN parts.state='inFlight' THEN parts.attempts ELSE excluded.attempts END,
                  error_code=CASE WHEN parts.state='inFlight' THEN parts.error_code ELSE NULL END,
                  etag=CASE WHEN parts.state='inFlight' THEN parts.etag ELSE NULL END,
                  task_id=CASE WHEN parts.state='inFlight' THEN parts.task_id ELSE NULL END,
                  temp_path=CASE WHEN parts.state='inFlight' THEN parts.temp_path ELSE NULL END;
                """
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK {
                    bindText(stmt, 1, p.sessionId)
                    sqlite3_bind_int64(stmt, 2, Int64(p.partNumber))
                    sqlite3_bind_int64(stmt, 3, p.offset)
                    sqlite3_bind_int64(stmt, 4, Int64(p.length))
                    bindTextOrNull(stmt, 5, p.url)
                    bindDateOrNull(stmt, 6, p.urlExpiresAt)
                    bindText(stmt, 7, p.state)
                    sqlite3_bind_int64(stmt, 8, Int64(p.attempts))
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
            db.exec("COMMIT;")
        }
    }

    /// Atomically claim the next schedulable part (planned, with a usable URL)
    /// and mark it inFlight — the guarded transition that prevents two delegate
    /// callbacks double-scheduling the same part.
    func claimNextSchedulablePart(sessionId: String, freshUntil: Date) -> JournalPart? {
        db.sync { handle in
            var found: JournalPart?
            db.exec("BEGIN IMMEDIATE;")
            let sql = """
            SELECT part_number, offset, length, url, url_expires_at, attempts
            FROM parts
            WHERE session_id=? AND state='planned' AND url IS NOT NULL
              AND (url_expires_at IS NULL OR url_expires_at > ?)
            ORDER BY part_number LIMIT 1;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, 1, sessionId)
                sqlite3_bind_int64(stmt, 2, Int64(freshUntil.timeIntervalSince1970))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let partNumber = Int(sqlite3_column_int64(stmt, 0))
                    found = JournalPart(
                        sessionId: sessionId,
                        partNumber: partNumber,
                        offset: sqlite3_column_int64(stmt, 1),
                        length: Int(sqlite3_column_int64(stmt, 2)),
                        url: columnText(stmt, 3),
                        urlExpiresAt: nil,
                        state: "inFlight",
                        taskId: nil, tempPath: nil, etag: nil, md5: nil,
                        attempts: Int(sqlite3_column_int64(stmt, 5)),
                        errorCode: nil
                    )
                }
            }
            sqlite3_finalize(stmt)

            if let part = found {
                var up: OpaquePointer?
                if sqlite3_prepare_v2(handle, "UPDATE parts SET state='inFlight' WHERE session_id=? AND part_number=?", -1, &up, nil) == SQLITE_OK {
                    bindText(up, 1, sessionId)
                    sqlite3_bind_int64(up, 2, Int64(part.partNumber))
                    sqlite3_step(up)
                }
                sqlite3_finalize(up)
            }
            db.exec("COMMIT;")
            return found
        }
    }

    func attachTask(sessionId: String, partNumber: Int, taskId: Int, tempPath: String, md5: String) {
        updatePart(sessionId, partNumber, set: "task_id=?, temp_path=?, md5=?", bind: { stmt in
            sqlite3_bind_int64(stmt, 1, Int64(taskId))
            self.bindText(stmt, 2, tempPath)
            self.bindText(stmt, 3, md5)
        })
    }

    // Both terminal transitions clear `task_id` so a finished part can never be
    // matched by a future task that happens to reuse the same URLSession
    // `taskIdentifier` (those integers are only unique within a live session and
    // are reused across app launches — see ChunkWindowManager's taskDescription
    // keying, which is the primary defense; this is belt-and-suspenders).
    func markUploaded(sessionId: String, partNumber: Int, etag: String) {
        updatePart(sessionId, partNumber, set: "state='uploaded', etag=?, task_id=NULL, drain_acknowledged=0", bind: { stmt in
            self.bindText(stmt, 1, etag)
        })
    }

    func markError(sessionId: String, partNumber: Int, newState: String, errorCode: String, attempts: Int) {
        updatePart(sessionId, partNumber, set: "state=?, error_code=?, attempts=?, task_id=NULL, drain_acknowledged=0", bind: { stmt in
            self.bindText(stmt, 1, newState)
            self.bindText(stmt, 2, errorCode)
            sqlite3_bind_int64(stmt, 3, Int64(attempts))
        })
    }

    /// Resume reconciliation: reset `inFlight` parts that have no live URLSession
    /// task back to `planned` so `fill()` reschedules them. A part is "live" when
    /// its stable key `"<sessionId>#<partNumber>"` is among [liveKeys] (the
    /// `taskDescription`s of the session's current tasks — see
    /// ChunkWindowManager). Keying on the description rather than the integer
    /// `taskIdentifier` is essential: identifiers are reused across app launches,
    /// so a stale id can false-match a live unrelated task and wrongly "adopt" an
    /// orphan, jamming the window. Without this, a part left `inFlight` by an
    /// interrupted run is never rescheduled (claim only picks `planned`) and never
    /// adopted, so the session stalls. Returns the number of parts reclaimed.
    @discardableResult
    func reclaimOrphanedInFlight(sessionId: String, liveKeys: Set<String>) -> Int {
        db.sync { handle in
            // Collect inFlight parts and decide which are orphaned (no live task
            // owns this exact session+part).
            var orphaned: [Int] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(
                handle,
                "SELECT part_number FROM parts WHERE session_id=? AND state='inFlight'",
                -1, &stmt, nil
            ) == SQLITE_OK {
                bindText(stmt, 1, sessionId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let partNumber = Int(sqlite3_column_int64(stmt, 0))
                    if !liveKeys.contains("\(sessionId)#\(partNumber)") {
                        orphaned.append(partNumber)
                    }
                }
            }
            sqlite3_finalize(stmt)

            guard !orphaned.isEmpty else { return 0 }
            db.exec("BEGIN;")
            for partNumber in orphaned {
                var up: OpaquePointer?
                if sqlite3_prepare_v2(
                    handle,
                    "UPDATE parts SET state='planned', task_id=NULL, temp_path=NULL WHERE session_id=? AND part_number=?",
                    -1, &up, nil
                ) == SQLITE_OK {
                    bindText(up, 1, sessionId)
                    sqlite3_bind_int64(up, 2, Int64(partNumber))
                    sqlite3_step(up)
                }
                sqlite3_finalize(up)
            }
            db.exec("COMMIT;")
            return orphaned.count
        }
    }

    // MARK: - Counts

    func inFlightCount(sessionId: String) -> Int {
        db.sync { _ in
            db.intCount(
                "SELECT COUNT(*) FROM parts WHERE session_id=? AND state='inFlight'",
                bind: { self.bindText($0, 1, sessionId) }
            )
        }
    }

    /// How many of the session's parts have finished uploading. Compared against
    /// the file's *true* part count (derived from fileSize/chunkSize) so the
    /// engine doesn't declare a session drained after only the first presigned
    /// batch — Dart hands native parts one batch at a time, so the journal holds
    /// fewer rows than the file has parts until every batch arrives.
    func uploadedCount(sessionId: String) -> Int {
        db.sync { _ in
            db.intCount(
                "SELECT COUNT(*) FROM parts WHERE session_id=? AND state='uploaded'",
                bind: { self.bindText($0, 1, sessionId) }
            )
        }
    }

    func allPartsUploaded(sessionId: String) -> Bool {
        db.sync { _ in
            db.intCount(
                "SELECT COUNT(*) FROM parts WHERE session_id=? AND state != 'uploaded'",
                bind: { self.bindText($0, 1, sessionId) }
            ) == 0
        }
    }

    func partsWithFreshUrlCount(sessionId: String, freshUntil: Date) -> Int {
        db.sync { _ in
            db.intCount(
                """
                SELECT COUNT(*) FROM parts
                WHERE session_id=? AND state='planned' AND url IS NOT NULL
                  AND (url_expires_at IS NULL OR url_expires_at > ?)
                """,
                bind: {
                    self.bindText($0, 1, sessionId)
                    sqlite3_bind_int64($0, 2, Int64(freshUntil.timeIntervalSince1970))
                }
            )
        }
    }

    func partsMissingUrlCount(sessionId: String) -> Int {
        db.sync { _ in
            db.intCount(
                """
                SELECT COUNT(*) FROM parts
                WHERE session_id=? AND state IN ('planned','error') AND (url IS NULL OR url='')
                """,
                bind: { self.bindText($0, 1, sessionId) }
            )
        }
    }

    /// True when parts remain but none can be scheduled (missing/expired URLs).
    func isUrlStalled(sessionId: String, freshUntil: Date) -> Bool {
        db.sync { handle in
            let inFlight = db.intCount(
                "SELECT COUNT(*) FROM parts WHERE session_id=? AND state='inFlight'",
                bind: { self.bindText($0, 1, sessionId) }
            )
            if inFlight > 0 { return false }

            var chunkSize: Int64 = 0
            var fileSize: Int64 = 0
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(
                handle,
                "SELECT chunk_size, file_size FROM sessions WHERE session_id=?",
                -1, &stmt, nil
            ) == SQLITE_OK {
                bindText(stmt, 1, sessionId)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    chunkSize = sqlite3_column_int64(stmt, 0)
                    fileSize = sqlite3_column_int64(stmt, 1)
                }
            }
            sqlite3_finalize(stmt)

            let uploaded = db.intCount(
                "SELECT COUNT(*) FROM parts WHERE session_id=? AND state='uploaded'",
                bind: { self.bindText($0, 1, sessionId) }
            )
            let total = chunkSize > 0
                ? Int((fileSize + chunkSize - 1) / chunkSize)
                : uploaded
            if uploaded >= total { return false }

            let schedulable = db.intCount(
                """
                SELECT COUNT(*) FROM parts
                WHERE session_id=? AND state='planned' AND url IS NOT NULL
                  AND (url_expires_at IS NULL OR url_expires_at > ?)
                """,
                bind: {
                    self.bindText($0, 1, sessionId)
                    sqlite3_bind_int64($0, 2, Int64(freshUntil.timeIntervalSince1970))
                }
            )
            if schedulable > 0 { return false }

            return (uploaded + inFlight) < total
        }
    }

    // MARK: - Temp files & drain

    /// The extracted chunk's temp file path for a part, so the delegate can clean
    /// it up after the transfer finishes. Delegate callbacks identify the part by
    /// the task's `taskDescription` ("<sessionId>#<partNumber>"), then look the
    /// path up here — never by the reuse-prone integer `taskIdentifier`.
    func tempPath(sessionId: String, partNumber: Int) -> String? {
        db.sync { handle in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT temp_path FROM parts WHERE session_id=? AND part_number=?", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, sessionId)
            sqlite3_bind_int64(stmt, 2, Int64(partNumber))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return columnText(stmt, 0)
        }
    }

    /// Drain completed/failed part results for Dart. Pass nil for all sessions.
    func drain(sessionId: String?) -> [[String: Any]] {
        db.sync { handle in
            var rows: [[String: Any]] = []
            let sql = sessionId == nil
                ? "SELECT session_id, part_number, state, etag, error_code, attempts FROM parts WHERE state IN ('uploaded','error') AND drain_acknowledged=0"
                : "SELECT session_id, part_number, state, etag, error_code, attempts FROM parts WHERE session_id=? AND state IN ('uploaded','error') AND drain_acknowledged=0"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return rows }
            defer { sqlite3_finalize(stmt) }
            if let sid = sessionId { bindText(stmt, 1, sid) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append([
                    "sessionId": columnText(stmt, 0) ?? "",
                    "partNumber": Int(sqlite3_column_int64(stmt, 1)),
                    "state": columnText(stmt, 2) ?? "",
                    "etag": columnText(stmt, 3) as Any,
                    "errorCode": columnText(stmt, 4) as Any,
                    "attempts": Int(sqlite3_column_int64(stmt, 5)),
                ])
            }
            return rows
        }
    }

    /// Mark exactly the drained part rows Dart acknowledged. Keep the rows:
    /// native still needs uploaded parts to compute session-drained state after
    /// relaunch. Deleting them makes a partially-drained session look like it
    /// lost completed work.
    func deleteDrainedParts(_ rows: [[String: Any]]) {
        db.sync { handle in
            db.exec("BEGIN;")
            for row in rows {
                guard let sessionId = row["sessionId"] as? String,
                      let partNumber = row["partNumber"] as? Int else { continue }
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(
                    handle,
                    "UPDATE parts SET drain_acknowledged=1 WHERE session_id=? AND part_number=? AND state IN ('uploaded','error')",
                    -1, &stmt, nil
                ) == SQLITE_OK {
                    bindText(stmt, 1, sessionId)
                    sqlite3_bind_int64(stmt, 2, Int64(partNumber))
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
            db.exec("COMMIT;")
        }
    }

    // MARK: - Helpers

    private func updatePart(
        _ sessionId: String, _ partNumber: Int, set: String,
        bind: (OpaquePointer?) -> Void
    ) {
        db.sync { handle in
            var stmt: OpaquePointer?
            // The bound `set` params come first (indices 1..n); the WHERE params
            // follow. Callers bind only the SET params; we bind WHERE after.
            let sql = "UPDATE parts SET \(set) WHERE session_id=? AND part_number=?"
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt)
            let whereBase = Int32(sqlite3_bind_parameter_count(stmt)) - 1
            bindText(stmt, whereBase, sessionId)
            sqlite3_bind_int64(stmt, whereBase + 1, Int64(partNumber))
            sqlite3_step(stmt)
        }
    }
}
