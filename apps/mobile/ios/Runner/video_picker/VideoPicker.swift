import Foundation
import UniformTypeIdentifiers

/// Protocol for video picker operations.
/// Equivalent to Android's VideoPicker interface.
protocol VideoPicker {
    
    /// The delegate to receive picker results
    var delegate: VideoPickerDelegate? { get set }
    
    /// Opens the system document picker for multiple video selection.
    /// Results are returned via the delegate.
    func pickVideos()
    
    /// Opens the system document picker for single video selection.
    /// Results are returned via the delegate.
    func pickSingleVideo()
}

/// Delegate protocol for receiving video picker results.
protocol VideoPickerDelegate: AnyObject {
    
    /// Called when multiple videos are picked.
    /// - Parameter urls: Array of file URL strings, or nil if cancelled
    func didPickVideos(_ urls: [String]?)
    
    /// Called when a single video is picked.
    /// - Parameter url: File URL string, or nil if cancelled
    func didPickSingleVideo(_ url: String?)
}
