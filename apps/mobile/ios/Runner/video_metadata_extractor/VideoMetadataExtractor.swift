import Foundation
import UIKit

/// Protocol for extracting metadata and thumbnails from video files.
/// Equivalent to Android's VideoMetadataExtractor interface.
protocol VideoMetadataExtractor {
    
    /// Extracts a thumbnail frame from a video.
    /// - Parameters:
    ///   - urlString: Video URL or file path
    ///   - timeMs: Time position in milliseconds
    /// - Returns: Path to saved thumbnail JPEG, or nil on error
    func extractThumbnail(urlString: String, timeMs: Int64) -> String?
    
    /// Gets the duration of a video.
    /// - Parameter urlString: Video URL or file path
    /// - Returns: Duration in seconds, or nil on error
    func getVideoDuration(urlString: String) -> Int?
    
    /// Gets basic metadata (filename, size, mime) for a video.
    /// - Parameter urlString: Video URL or file path
    /// - Returns: Dictionary with optional keys: name, size (bytes), mimeType
    func getVideoMetadata(urlString: String) -> [String: Any?]
    
    /// Opens a video in the system's default viewer.
    /// - Parameter urlString: Video URL
    /// - Returns: true if video was opened successfully
    func openVideoInViewer(urlString: String) -> Bool
    
    /// Saves a video to the device photo library.
    /// - Parameter sourcePath: Path to the source video file
    /// - Returns: true if video was saved successfully
    func saveVideoToGallery(sourcePath: String) -> Bool
}
