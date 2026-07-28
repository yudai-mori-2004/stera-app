import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 — Native windowed upload engine (CONTRACT).
//
// The sole upload engine — the legacy
//     `IosBackgroundUploader` triad was removed.
//
// Triad rule (CLAUDE.md / practices 05): this Contract file imports no Flutter.
// The Impl (`ChunkWindowManager` + `ChunkExtractor` + journal) does all the
// platform work; the `MethodChannelHandler` is the only file importing Flutter.
// ─────────────────────────────────────────────────────────────────────────────

/// One part to transfer: a slice of the source file with a fresh presigned URL.
/// Bytes never cross the channel — only these descriptors do.
public struct UploadPartPlan {
    public let partNumber: Int
    public let offset: Int64
    public let length: Int
    public let url: String
    public let urlExpiresAt: Date?

    public init(
        partNumber: Int,
        offset: Int64,
        length: Int,
        url: String,
        urlExpiresAt: Date?
    ) {
        self.partNumber = partNumber
        self.offset = offset
        self.length = length
        self.url = url
        self.urlExpiresAt = urlExpiresAt
    }
}

/// The manifest Dart hands native (or native reloads from its journal) to drive
/// one session's transfer. `parts` carries only the parts that still need
/// transferring, each with a fresh URL.
public struct UploadSessionManifest {
    public let sessionId: String
    /// Resolved absolute file URL; security-scoped access is handled natively.
    public let fileUrl: String
    public let contentType: String
    public let fileSize: Int64
    public let chunkSize: Int
    /// Max in-flight parts ⇒ disk ceiling = windowSize × chunkSize.
    public let windowSize: Int
    public let parts: [UploadPartPlan]

    public init(
        sessionId: String,
        fileUrl: String,
        contentType: String,
        fileSize: Int64,
        chunkSize: Int,
        windowSize: Int,
        parts: [UploadPartPlan]
    ) {
        self.sessionId = sessionId
        self.fileUrl = fileUrl
        self.contentType = contentType
        self.fileSize = fileSize
        self.chunkSize = chunkSize
        self.windowSize = windowSize
        self.parts = parts
    }
}

/// The native surface (doc 07 §3). Dart decides *what* to upload; native
/// decides *how* and keeps the window full even while Dart is dead. Results flow
/// back over the event channel (`partCompleted`, `partFailed`, `needUrls`,
/// `sessionDrained`, `progress`).
public protocol IosWindowedUploader {
    /// Begin (or resume) a session: persist the manifest to the journal and
    /// start filling the in-flight window.
    func beginSession(_ manifest: UploadSessionManifest)

    /// Supply fresh presigned URLs for parts that ran dry (answers `needUrls`).
    func provideUrls(sessionId: String, parts: [UploadPartPlan])

    /// User pause: let in-flight tasks finish, stop refilling.
    func pauseSession(sessionId: String)

    /// User cancel: cancel tasks, abort temp files, drop journal rows.
    func cancelSession(sessionId: String)

    /// Hand Dart the journal rows accumulated while it was dead so it can apply
    /// them to Drift, then delete exactly the rows it received (never "delete
    /// all"). Pass `nil` to drain every session.
    func drainJournal(sessionId: String?) -> [[String: Any]]

    /// Bytes free on the volume where chunk temp files are extracted — the
    /// figure Dart's disk pre-flight gates a session on (doc 04 §4). Reads
    /// "available for important usage" so it matches what iOS will let us write.
    func freeDiskBytes() -> Int64

    /// Cap on in-flight part tasks while the app is FOREGROUNDED. Dart's
    /// adaptive tuner (AIMD over measured part durations) varies this within
    /// 5–10 to match current network conditions; `httpMaximumConnectionsPerHost`
    /// is the static ceiling it moves under. Backgrounded sessions ignore the
    /// gate and fill the whole window — Dart is frozen then, and the backlog is
    /// what lets the daemon progress without app wakes. Values are clamped to
    /// ≥ 1; the setting is process-lifetime (not journaled), so a relaunched
    /// engine starts at the default until Dart pushes again.
    func setTransferConcurrency(maxInFlight: Int)
}

/// Runtime manager surface for the native windowed uploader implementation.
/// Extends the upload contract with the two process-level callbacks that are
/// wired by AppDelegate/MethodChannelHandler rather than invoked from Dart.
public protocol ChunkWindowManaging: IosWindowedUploader {
    var eventSink: (([String: Any]) -> Void)? { get set }
    var backgroundCompletionHandler: (() -> Void)? { get set }
    /// Foreground/background hint from the Flutter app lifecycle. Drives whether
    /// native posts user-facing notifications (it does only when not foregrounded).
    var appForegrounded: Bool { get set }
}
