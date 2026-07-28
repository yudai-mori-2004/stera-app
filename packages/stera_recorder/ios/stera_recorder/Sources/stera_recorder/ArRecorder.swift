import Foundation

/// Protocol for AR recording operations using ARKit.
/// Captures synchronized RGB video, IMU data, camera poses, point clouds,
/// and depth data (if supported on LiDAR devices).
protocol ArRecorder {
    var onLowStorageWarning: (() -> Void)? { get set }
    var onStorageCritical: (() -> Void)? { get set }
    func initializeSession(preferences: [String: Any?]?) -> [String: Any?]
    func startRecording(config: RecordingConfig) -> [String: Any?]
    func pauseRecording() -> [String: Any?]
    func resumeRecording() -> [String: Any?]
    func cancelRecording() -> [String: Any?]
    func stopRecording() -> [String: Any?]
    func getRecordingState() -> [String: Any?]
    func checkArAvailability() -> [String: Any?]
    func disposeSession()

    /// Active session directory if a recording is prepared or in progress.
    func currentSessionDirectory() -> URL?
}
