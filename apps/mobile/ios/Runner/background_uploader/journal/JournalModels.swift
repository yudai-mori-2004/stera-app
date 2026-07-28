import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Row models for the native transfer journal — one struct per table.
// ─────────────────────────────────────────────────────────────────────────────

struct JournalSession {
    let sessionId: String
    let fileUrl: String
    let chunkSize: Int
    let fileSize: Int64
    let contentType: String
    let windowSize: Int
    let state: String
}

struct JournalPart {
    let sessionId: String
    let partNumber: Int
    let offset: Int64
    let length: Int
    let url: String?
    let urlExpiresAt: Date?
    let state: String          // planned | inFlight | uploaded | error
    let taskId: Int?
    let tempPath: String?
    let etag: String?
    let md5: String?
    let attempts: Int
    let errorCode: String?
}
