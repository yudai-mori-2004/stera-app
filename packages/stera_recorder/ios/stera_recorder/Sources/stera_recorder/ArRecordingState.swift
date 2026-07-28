import Foundation

/// Enumeration of possible states for the AR recording session.
enum ArRecordingState: String {
    case uninitialized = "UNINITIALIZED"
    case initializing = "INITIALIZING"
    case ready = "READY"
    case recording = "RECORDING"
    case paused = "PAUSED"
    case stopping = "STOPPING"
    case cancelling = "CANCELLING"
    case error = "ERROR"
    case disposed = "DISPOSED"
}

/// Enumeration of ARKit tracking states.
enum ArTrackingState: String {
    case tracking = "TRACKING"
    case paused = "PAUSED"
    case stopped = "STOPPED"
}
