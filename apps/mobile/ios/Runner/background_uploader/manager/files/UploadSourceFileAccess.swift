import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Collaborator (Contract) — security-scoped access + data-protection handling
// for upload source files. Decomposed out of ChunkWindowManager per practices
// 05; the engine drives it, this owns the file-system bookkeeping.
//
// Not internally synchronized: the engine calls these from its serial work
// queue (the same queue the transfer window runs on), so a lock would be
// redundant. Callers outside that queue must not use it directly.
// ─────────────────────────────────────────────────────────────────────────────

public protocol UploadSourceFileAccess: AnyObject {
    /// Parse a stored file-url string back into a `URL` (absolute string or path).
    func resolve(_ fileUrl: String) -> URL

    /// Start security-scoped access for `fileUrl`, tracked so it's held at most
    /// once; a no-op if already held.
    func beginAccess(_ fileUrl: String)

    /// Balance a prior `beginAccess`; a no-op if not currently held.
    func endAccess(_ fileUrl: String)

    /// Relax the source's data protection to `.completeUntilFirstUserAuthentication`
    /// so `nsurlsessiond` can re-read it on every window refill while the device
    /// is locked (req 2). Best-effort — an external source we can't modify just
    /// fails harmlessly.
    func relaxProtection(_ fileUrl: String)
}
