import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 — native transfer journal (facade). Compiles in Xcode.
//
// A small SQLite DB (Library/Application Support) holding only *transfer* state
// for active sessions — fully rebuildable from the Dart Drift DB + ListParts.
// Replaces the legacy UserDefaults plist (no transactions, no concurrent
// read-modify-write safety — bugs B2/B3). Gives atomic
// `UPDATE … WHERE state='planned' … LIMIT 1` semantics from the URLSession
// delegate queue.
//
// Per practices 05 "Splitting large impls", this is a thin facade composing
// focused collaborators that share one serial connection (so the engine still
// talks to a single `UploadJournal`):
//   • JournalDatabase — connection, serial queue, schema + migrations
//   • SessionStore    — the `sessions` table + notification flags
//   • PartStore       — the `parts` table, atomic claim/reclaim, drain handshake
// ─────────────────────────────────────────────────────────────────────────────

final class UploadJournal {
    private let database: JournalDatabase
    private let sessions: SessionStore
    private let parts: PartStore

    init(path: URL? = nil) {
        let database = JournalDatabase(path: path)
        self.database = database
        self.sessions = SessionStore(db: database)
        self.parts = PartStore(db: database)
    }

    // MARK: - Sessions

    func upsertSession(
        sessionId: String, fileUrl: String, chunkSize: Int, fileSize: Int64,
        contentType: String, windowSize: Int, state: String
    ) {
        sessions.upsertSession(
            sessionId: sessionId, fileUrl: fileUrl, chunkSize: chunkSize,
            fileSize: fileSize, contentType: contentType, windowSize: windowSize,
            state: state
        )
    }

    func setSessionState(_ sessionId: String, _ state: String) {
        sessions.setSessionState(sessionId, state)
    }

    func sessionState(_ sessionId: String) -> String? {
        sessions.sessionState(sessionId)
    }

    func totalParts(for sessionId: String) -> Int {
        sessions.totalParts(for: sessionId)
    }

    func sessionConfig(_ sessionId: String) -> JournalSession? {
        sessions.sessionConfig(sessionId)
    }

    func activeSessionIds() -> [String] {
        sessions.activeSessionIds()
    }

    func allSessionIds() -> [String] {
        sessions.allSessionIds()
    }

    func deleteSession(_ sessionId: String) {
        sessions.deleteSession(sessionId)
    }

    // MARK: - Notification flags

    func stallNotificationSent(_ sessionId: String) -> Bool {
        sessions.stallNotificationSent(sessionId)
    }

    func finishNotificationSent(_ sessionId: String) -> Bool {
        sessions.finishNotificationSent(sessionId)
    }

    func markStallNotificationSent(_ sessionId: String) {
        sessions.markStallNotificationSent(sessionId)
    }

    func markFinishNotificationSent(_ sessionId: String) {
        sessions.markFinishNotificationSent(sessionId)
    }

    func clearStallNotificationSent(_ sessionId: String) {
        sessions.clearStallNotificationSent(sessionId)
    }

    func progressNotifiedBucket(_ sessionId: String) -> Int {
        sessions.progressNotifiedBucket(sessionId)
    }

    func setProgressNotifiedBucket(_ sessionId: String, _ bucket: Int) {
        sessions.setProgressNotifiedBucket(sessionId, bucket)
    }

    func videoCounts() -> (completed: Int, total: Int) {
        sessions.videoCounts()
    }

    // MARK: - Parts

    func upsertParts(_ partsToInsert: [JournalPart]) {
        parts.upsertParts(partsToInsert)
    }

    func claimNextSchedulablePart(sessionId: String, freshUntil: Date) -> JournalPart? {
        parts.claimNextSchedulablePart(sessionId: sessionId, freshUntil: freshUntil)
    }

    func attachTask(sessionId: String, partNumber: Int, taskId: Int, tempPath: String, md5: String)
    {
        parts.attachTask(
            sessionId: sessionId, partNumber: partNumber, taskId: taskId, tempPath: tempPath,
            md5: md5)
    }

    func markUploaded(sessionId: String, partNumber: Int, etag: String) {
        parts.markUploaded(sessionId: sessionId, partNumber: partNumber, etag: etag)
    }

    func markError(
        sessionId: String, partNumber: Int, newState: String, errorCode: String, attempts: Int
    ) {
        parts.markError(
            sessionId: sessionId, partNumber: partNumber, newState: newState, errorCode: errorCode,
            attempts: attempts)
    }

    @discardableResult
    func reclaimOrphanedInFlight(sessionId: String, liveKeys: Set<String>) -> Int {
        parts.reclaimOrphanedInFlight(sessionId: sessionId, liveKeys: liveKeys)
    }

    func inFlightCount(sessionId: String) -> Int {
        parts.inFlightCount(sessionId: sessionId)
    }

    func uploadedCount(sessionId: String) -> Int {
        parts.uploadedCount(sessionId: sessionId)
    }

    func allPartsUploaded(sessionId: String) -> Bool {
        parts.allPartsUploaded(sessionId: sessionId)
    }

    func partsWithFreshUrlCount(sessionId: String, freshUntil: Date) -> Int {
        parts.partsWithFreshUrlCount(sessionId: sessionId, freshUntil: freshUntil)
    }

    func partsMissingUrlCount(sessionId: String) -> Int {
        parts.partsMissingUrlCount(sessionId: sessionId)
    }

    func isUrlStalled(sessionId: String, freshUntil: Date) -> Bool {
        parts.isUrlStalled(sessionId: sessionId, freshUntil: freshUntil)
    }

    func tempPath(sessionId: String, partNumber: Int) -> String? {
        parts.tempPath(sessionId: sessionId, partNumber: partNumber)
    }

    func drain(sessionId: String?) -> [[String: Any]] {
        parts.drain(sessionId: sessionId)
    }

    func deleteDrainedParts(_ rows: [[String: Any]]) {
        parts.deleteDrainedParts(rows)
    }
}
