import Foundation
import Foundation
import UniformTypeIdentifiers

/// Implementation of SecurityScopedURLHelper for iOS Security-Scoped URL operations.
/// Uses security-scoped bookmarks to maintain persistent access to files picked via document picker.
public class SecurityScopedURLHelperImpl {
    
    /// UserDefaults key prefix for storing bookmarks
    private let bookmarkKeyPrefix = "io.rootlens.app.bookmark."
    
    /// Track URLs currently being accessed (thread-safe)
    private var accessingURLs: Set<String> = []
    
    /// Serial queue for thread-safe access to accessingURLs
    private let accessingURLsQueue = DispatchQueue(label: "io.rootlens.app.securityScopedURLHelper.accessingURLs")
    
    // MARK: - Bookmark Management
    
    public func saveSecurityScopedBookmark(urlString: String) -> Bool {
        // appsupport:// URLs don't need bookmarks - they're our own files in app sandbox
        if urlString.hasPrefix("appsupport://") {
            print("✅ appsupport:// URL, no bookmark needed: \(urlString)")
            return true
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL string: \(urlString)")
            return false
        }
        
        // Files in app sandbox don't need security-scoped access
        if isInAppSandbox(url: url) {
            print("✅ File is in app sandbox, no bookmark needed: \(urlString)")
            return true
        }
        
        // Check if file exists and is readable without security-scoped access
        // This handles files that were copied to accessible locations (e.g., from PHPicker)
        if FileManager.default.isReadableFile(atPath: url.path) {
            print("✅ File is readable without security-scoped access: \(urlString)")
            return true
        }
        
        // Try to start security-scoped access for document picker URLs
        let didStartAccess = url.startAccessingSecurityScopedResource()
        
        // If we couldn't start access AND file isn't readable, we have a problem
        if !didStartAccess && !FileManager.default.isReadableFile(atPath: url.path) {
            print("❌ Could not access file: \(urlString)")
            return false
        }
        
        // Only stop access if we started it
        defer { 
            if didStartAccess {
                url.stopAccessingSecurityScopedResource() 
            }
        }
        
        do {
            // Create a bookmark (works for both security-scoped and regular file URLs)
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // Save bookmark to UserDefaults (use URL string directly for stable key)
            let key = bookmarkKeyPrefix + urlString
            UserDefaults.standard.set(bookmarkData, forKey: key)
            
            print("✅ Bookmark saved for: \(urlString)")
            return true
        } catch {
            // Bookmark creation can fail for non-security-scoped URLs, but that's OK
            // as long as the file is still accessible
            if FileManager.default.isReadableFile(atPath: url.path) {
                print("⚠️ Bookmark creation failed but file is accessible: \(urlString)")
                return true
            }
            print("❌ Error creating bookmark: \(error)")
            return false
        }
    }
    
    public func releaseSecurityScopedBookmark(urlString: String) -> Bool {
        let key = bookmarkKeyPrefix + urlString
        
        // Stop accessing if currently accessing
        var shouldStop = false
        accessingURLsQueue.sync {
            shouldStop = accessingURLs.contains(urlString)
        }
        if shouldStop {
            stopAccessing(urlString: urlString)
        }
        
        // Remove from UserDefaults
        UserDefaults.standard.removeObject(forKey: key)
        print("✅ Security-scoped bookmark released for: \(urlString)")
        return true
    }
    
    public func hasBookmark(urlString: String) -> Bool {
        // appsupport:// URLs are always accessible - they're our own files in app sandbox
        if urlString.hasPrefix("appsupport://") {
            print("✅ appsupport:// URL, always has access: \(urlString)")
            return true
        }
        
        guard let url = URL(string: urlString) else {
            return false
        }
        
        // App always has access to sandbox files
        if isInAppSandbox(url: url) {
            return true
        }
        
        // Check if file is directly readable (e.g., copied files from PHPicker)
        if FileManager.default.isReadableFile(atPath: url.path) {
            return true
        }
        
        let key = bookmarkKeyPrefix + urlString
        
        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            return false
        }
        
        // Try to resolve the bookmark to verify it's still valid
        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("⚠️ Bookmark is stale for: \(urlString), refreshing")
                return refreshBookmark(urlString: urlString, url: resolvedURL)
            }
            
            return true
        } catch {
            print("❌ Error resolving bookmark: \(error)")
            return false
        }
    }
    
    // MARK: - Security-Scoped Access
    
    public func startAccessing(urlString: String) -> Bool {
        // appsupport:// URLs are always accessible - they're our own files in app sandbox
        if urlString.hasPrefix("appsupport://") {
            print("✅ appsupport:// URL, always accessible: \(urlString)")
            return true
        }
        
        // First check if file is already accessible without security-scoped access
        if let url = URL(string: urlString) {
            if isInAppSandbox(url: url) || FileManager.default.isReadableFile(atPath: url.path) {
                print("✅ File is accessible without security-scoped access: \(urlString)")
                return true
            }
        }
        
        // Try to use saved bookmark
        let key = bookmarkKeyPrefix + urlString
        
        if let bookmarkData = UserDefaults.standard.data(forKey: key) {
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    print("⚠️ Bookmark is stale for: \(urlString), refreshing")
                    if refreshBookmark(urlString: urlString, url: resolvedURL) {
                        return startAccessing(urlString: urlString)
                    }
                }
                
                if resolvedURL.startAccessingSecurityScopedResource() {
                    accessingURLsQueue.sync {
                        accessingURLs.insert(urlString)
                    }
                    print("✅ Started accessing via bookmark: \(urlString)")
                    return true
                }
            } catch {
                print("❌ Error resolving bookmark for access: \(error)")
            }
        }
        
        // Fallback: try direct URL access
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL string: \(urlString)")
            return false
        }
        
        if url.startAccessingSecurityScopedResource() {
            accessingURLsQueue.sync {
                accessingURLs.insert(urlString)
            }
            print("✅ Started accessing directly: \(urlString)")
            return true
        }
        
        print("❌ Could not start accessing: \(urlString)")
        return false
    }
    
    public func stopAccessing(urlString: String) {
        var shouldStop = false
        accessingURLsQueue.sync {
            shouldStop = accessingURLs.contains(urlString)
        }
        guard shouldStop else { return }
        
        if let url = URL(string: urlString) {
            url.stopAccessingSecurityScopedResource()
            accessingURLsQueue.sync {
                accessingURLs.remove(urlString)
            }
            print("✅ Stopped accessing: \(urlString)")
        }
    }
    
    // MARK: - File Operations
    
    public func getFileSize(urlString: String) -> Int64? {
        print("🔍 SecurityScopedURLHelper: getFileSize for \(urlString)")
        guard let url = resolveURL(urlString: urlString) else {
            print("❌ SecurityScopedURLHelper: Could not resolve URL for \(urlString)")
            return nil
        }

        let shouldStopAccessing = startAccessingIfNeeded(url: url, urlString: urlString)
        defer { if shouldStopAccessing { stopAccessing(urlString: urlString) } }

        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .totalFileSizeKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
            ])

            // iCloud placeholder: file lives in iCloud and isn't fully downloaded locally.
            // .fileSizeKey can return 0 for a placeholder stub while the real size is in
            // .totalFileSizeKey. Returning 0 here cascades to a backend 400 in multipart_presign,
            // so fail fast with nil and kick off a download so a retry can succeed.
            if resourceValues.isUbiquitousItem == true,
               let status = resourceValues.ubiquitousItemDownloadingStatus,
               status != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                print("⏳ SecurityScopedURLHelper: iCloud file not downloaded (status=\(status.rawValue)) for \(urlString); started download")
                return nil
            }

            if let size = resourceValues.fileSize, size > 0 {
                print("✅ SecurityScopedURLHelper: File size for \(urlString) is \(size)")
                return Int64(size)
            }
            if let total = resourceValues.totalFileSize, total > 0 {
                print("⚠️ SecurityScopedURLHelper: fileSize was 0/nil but totalFileSize=\(total) for \(urlString) — likely not downloaded")
                return nil
            }
            print("❌ SecurityScopedURLHelper: File size is 0 or unavailable for \(urlString)")
        } catch {
            print("❌ SecurityScopedURLHelper: Error getting file size for \(urlString): \(error)")
        }

        return nil
    }

    public func getFileMetadata(urlString: String) -> [String: Any?] {
        print("🔍 SecurityScopedURLHelper: getFileMetadata for \(urlString)")
        var metadata: [String: Any?] = [:]
        
        guard let url = resolveURL(urlString: urlString) else { 
            print("❌ SecurityScopedURLHelper: Could not resolve URL for \(urlString)")
            return metadata 
        }
        
        let shouldStopAccessing = startAccessingIfNeeded(url: url, urlString: urlString)
        defer { if shouldStopAccessing { stopAccessing(urlString: urlString) } }
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .nameKey,
                .fileSizeKey,
                .contentTypeKey
            ])
            
            metadata["name"] = resourceValues.name
            
            if let size = resourceValues.fileSize {
                metadata["size"] = Int64(size)
            }
            
            if let contentType = resourceValues.contentType {
                metadata["mimeType"] = contentType.preferredMIMEType
            }
            print("✅ SecurityScopedURLHelper: Metadata retrieved for \(urlString)")
        } catch {
            print("❌ SecurityScopedURLHelper: Error getting file metadata for \(urlString): \(error)")
        }
        
        return metadata
    }
    
    public func readChunk(urlString: String, offset: Int64, length: Int) -> Data? {
        guard let url = resolveURL(urlString: urlString) else { return nil }
        
        let shouldStopAccessing = startAccessingIfNeeded(url: url, urlString: urlString)
        defer { if shouldStopAccessing { stopAccessing(urlString: urlString) } }
        
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            
            // Seek to offset
            try fileHandle.seek(toOffset: UInt64(offset))
            
            // Read chunk
            if let data = try fileHandle.read(upToCount: length) {
                return data
            }
        } catch {
            print("❌ Error reading chunk: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    /// Checks if a URL is within the app's sandbox (temp, Documents, Caches, Application Support directories).
    /// Files in the sandbox don't need security-scoped access since the app already owns them.
    private func isInAppSandbox(url: URL) -> Bool {
        let sandboxDirs = [
            FileManager.default.temporaryDirectory,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ].compactMap { $0?.standardizedFileURL.path }
        
        let urlPath = url.standardizedFileURL.path
        let result = sandboxDirs.contains { urlPath.hasPrefix($0) }
        print("🔍 SecurityScopedURLHelper: isInAppSandbox for \(urlPath) -> \(result)")
        return result
    }
    
    private func resolveURL(urlString: String) -> URL? {
        // Handle custom appsupport:// scheme for relative paths
        // Format: appsupport://uploads/filename.mp4 -> {AppSupport}/uploads/filename.mp4
        if urlString.hasPrefix("appsupport://") {
            let relativePath = String(urlString.dropFirst("appsupport://".count))
            do {
                let appSupportDir = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
                let resolvedURL = appSupportDir.appendingPathComponent(relativePath)
                print("🔍 SecurityScopedURLHelper: Resolved appsupport:// to \(resolvedURL.path)")
                return resolvedURL
            } catch {
                print("❌ SecurityScopedURLHelper: Failed to resolve appsupport:// URL: \(error)")
                return nil
            }
        }
        
        // Handle custom documents:// scheme for relative paths
        // Format: documents://ar_sessions/session_xxx/file.mcap -> {Documents}/ar_sessions/session_xxx/file.mcap
        if urlString.hasPrefix("documents://") {
            let relativePath = String(urlString.dropFirst("documents://".count))
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let resolvedURL = documentsDir.appendingPathComponent(relativePath)
            print("🔍 SecurityScopedURLHelper: Resolved documents:// to \(resolvedURL.path)")
            return resolvedURL
        }

        // First try to resolve from saved bookmark
        let key = bookmarkKeyPrefix + urlString
        
        if let bookmarkData = UserDefaults.standard.data(forKey: key) {
            print("🔍 SecurityScopedURLHelper: Found bookmark data for \(urlString)")
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    print("⚠️ SecurityScopedURLHelper: Bookmark is stale for: \(urlString), refreshing")
                    _ = refreshBookmark(urlString: urlString, url: resolvedURL)
                }
                print("✅ SecurityScopedURLHelper: Resolved bookmark to path: \(resolvedURL.path)")
                return resolvedURL
            } catch {
                print("❌ SecurityScopedURLHelper: Error resolving bookmark: \(error)")
            }
        }
        
        // Fallback to direct URL
        // If it's a file URL, ensure we handle percent-encoding correctly
        var url: URL?
        if urlString.hasPrefix("file://") {
            // URL(string:) handles percent-encoded strings correctly and .path will be decoded
            url = URL(string: urlString)
            
            // If URL(string:) fails, it might be due to unencoded spaces
            if url == nil, let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                url = URL(string: encoded)
            }
        } else if urlString.hasPrefix("/") {
            // Plain absolute file path — use fileURLWithPath which handles paths correctly
            url = URL(fileURLWithPath: urlString)
        } else {
            url = URL(string: urlString)
        }
        
        if let resolvedURL = url {
            print("🔍 SecurityScopedURLHelper: Resolved to direct URL path: \(resolvedURL.path)")
            return resolvedURL
        } else {
            print("❌ SecurityScopedURLHelper: Failed to create URL from string: \(urlString)")
            return nil
        }
    }
    
    private func startAccessingIfNeeded(url: URL, urlString: String) -> Bool {
        var isAlreadyAccessing = false
        accessingURLsQueue.sync {
            isAlreadyAccessing = accessingURLs.contains(urlString)
        }
        if isAlreadyAccessing {
            print("🔍 SecurityScopedURLHelper: Already accessing \(urlString)")
            return false // Already accessing
        }
        
        // No security-scoped access needed for sandbox files
        if isInAppSandbox(url: url) {
            print("🔍 SecurityScopedURLHelper: No access needed (in sandbox) for \(urlString)")
            return false
        }
        
        // No security-scoped access needed if file is directly readable
        if FileManager.default.isReadableFile(atPath: url.path) {
            print("🔍 SecurityScopedURLHelper: No access needed (readable) for \(urlString)")
            return false
        }
        
        if url.startAccessingSecurityScopedResource() {
            print("✅ SecurityScopedURLHelper: Started security-scoped access for \(urlString)")
            accessingURLsQueue.sync {
                accessingURLs.insert(urlString)
            }
            return true
        }
        
        print("❌ SecurityScopedURLHelper: Failed to start security-scoped access for \(urlString)")
        return false
    }

    private func refreshBookmark(urlString: String, url: URL) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let key = bookmarkKeyPrefix + urlString
            UserDefaults.standard.set(bookmarkData, forKey: key)
            print("✅ Refreshed bookmark for: \(urlString)")
            return true
        } catch {
            print("❌ Failed to refresh bookmark: \(error)")
            return false
        }
    }
}
