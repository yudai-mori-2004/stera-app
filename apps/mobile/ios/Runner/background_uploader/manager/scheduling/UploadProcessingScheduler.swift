import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Collaborator (Contract) — BGProcessingTask scheduling for the windowed
// uploader. Decomposed out of ChunkWindowManager per practices 05: this owns
// the OS scheduling handshake, the engine supplies the refill work to run when
// a slot is granted.
// ─────────────────────────────────────────────────────────────────────────────

public protocol UploadProcessingScheduler: AnyObject {
    /// Register the BGProcessingTask handler. Call once from AppDelegate
    /// `didFinishLaunching`. The identifier must be listed in Info.plist
    /// `BGTaskSchedulerPermittedIdentifiers`. No-op below iOS 13.
    func register()

    /// Ask iOS for the next processing slot (typically overnight, on power) so the
    /// engine can refill windows that ran dry while suspended. No-op below iOS 13.
    func schedule()
}
