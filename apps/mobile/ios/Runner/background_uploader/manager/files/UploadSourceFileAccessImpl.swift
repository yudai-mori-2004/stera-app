import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Collaborator (Impl) — tracks the set of source urls under security-scoped
// access and applies the locked-readable protection class. Logging is injected
// so it lands in the same diagnostics ring buffer as the rest of the engine.
// ─────────────────────────────────────────────────────────────────────────────

public final class UploadSourceFileAccessImpl: UploadSourceFileAccess {
    private var accessed: Set<String> = []
    private let log: (String) -> Void

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    public func resolve(_ fileUrl: String) -> URL {
        URL(string: fileUrl) ?? URL(fileURLWithPath: fileUrl)
    }

    public func beginAccess(_ fileUrl: String) {
        guard !accessed.contains(fileUrl) else { return }
        if resolve(fileUrl).startAccessingSecurityScopedResource() {
            accessed.insert(fileUrl)
        }
    }

    public func endAccess(_ fileUrl: String) {
        guard accessed.contains(fileUrl) else { return }
        resolve(fileUrl).stopAccessingSecurityScopedResource()
        accessed.remove(fileUrl)
    }

    public func relaxProtection(_ fileUrl: String) {
        // `.completeUntilFirstUserAuthentication` keeps the file readable after the
        // first unlock since boot (the same class the chunk temp files use) while
        // preserving cold-boot-at-rest encryption. Done foregrounded/unlocked at
        // beginSession, when the attribute is writable.
        let url = resolve(fileUrl)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            log("relaxProtection: set completeUntilFirstUserAuthentication")
        } catch {
            log("relaxProtection: failed (\(error.localizedDescription))")
        }
    }
}
