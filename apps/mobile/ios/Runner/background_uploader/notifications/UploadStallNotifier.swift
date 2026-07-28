import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Native local notifications when uploads stall or need the app reopened.
// Contract — no Flutter imports (practice 05).
// ─────────────────────────────────────────────────────────────────────────────

public protocol UploadStallNotifier {
    /// Post when presigned URLs ran dry and Dart must reopen to continue.
    func notifyUrlStall(sessionId: String, uploaded: Int, total: Int)

    /// Post when a background transfer failed and the window parked with nothing
    /// in flight — the device went offline mid-transfer or the server rejected a
    /// part, so the upload can't continue until connectivity returns or the app
    /// is reopened.
    func notifyTransferStall(sessionId: String)

    /// Post when all parts uploaded but finalize/register needs a foreground app.
    func notifyFinishNeeded(sessionId: String)

    /// Update the single ongoing upload-progress notification while the app is
    /// backgrounded. Mirrors the Dart UI's "X/Y · Uploading P%" — `completed`/
    /// `total` are video counts, `percent` is the current video's rounded
    /// progress. Replaces the existing banner in place (stable identifier).
    func notifyProgress(completed: Int, total: Int, percent: Int)
}
