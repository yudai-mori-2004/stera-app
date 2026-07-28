import Foundation

import Foundation

/// Protocol for iOS Security-Scoped URL operations.
/// Equivalent to Android's ContentUriHelper for handling persistent access to files
/// picked via document picker.
public protocol SecurityScopedURLHelper {
    
    /// Saves a security-scoped bookmark for a URL.
    /// This allows the URL to remain valid even after app restart.
    /// - Parameter urlString: The file URL string
    /// - Returns: true if bookmark was successfully saved
    func saveSecurityScopedBookmark(urlString: String) -> Bool
    
    /// Releases/deletes the saved bookmark for a URL.
    /// - Parameter urlString: The file URL string
    /// - Returns: true if bookmark was successfully released
    func releaseSecurityScopedBookmark(urlString: String) -> Bool
    
    /// Checks if app has a saved bookmark for this URL.
    /// - Parameter urlString: The file URL string
    /// - Returns: true if bookmark exists and is still valid
    func hasBookmark(urlString: String) -> Bool
    
    /// Gets the file size for a URL.
    /// - Parameter urlString: The file URL string
    /// - Returns: File size in bytes, or nil if unavailable
    func getFileSize(urlString: String) -> Int64?
    
    /// Gets file metadata (name, size, mimeType).
    /// - Parameter urlString: The file URL string
    /// - Returns: Dictionary containing metadata
    func getFileMetadata(urlString: String) -> [String: Any?]
    
    /// Reads a chunk of bytes from a file.
    /// - Parameters:
    ///   - urlString: The file URL string
    ///   - offset: Starting position in bytes
    ///   - length: Number of bytes to read
    /// - Returns: Data of the chunk, or nil on error
    func readChunk(urlString: String, offset: Int64, length: Int) -> Data?
    
    /// Starts security-scoped access to a URL (must call before file operations).
    /// - Parameter urlString: The file URL string
    /// - Returns: true if access was successfully started
    func startAccessing(urlString: String) -> Bool
    
    /// Stops security-scoped access to a URL (must call after file operations).
    /// - Parameter urlString: The file URL string
    func stopAccessing(urlString: String)
}
