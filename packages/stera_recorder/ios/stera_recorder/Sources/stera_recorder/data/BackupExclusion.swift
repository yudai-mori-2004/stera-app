import Foundation

enum BackupExclusion {
    /// Marks the URL (file or directory) as excluded from iCloud / iTunes backup.
    /// Idempotent — safe to call on every session start.
    static func exclude(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try mutable.setResourceValues(values)
        } catch {
            print("⚠️ BackupExclusion: failed to exclude \(url.path): \(error.localizedDescription)")
        }
    }
}
