import Foundation

/// Data container for depth frame binary data.
struct DepthFrameData {
    let bytes: Data
    let validSize: Int
    let width: Int
    let height: Int
    let bytesPerPixel: Int
    let pixelStride: Int
    let rowStride: Int
    let unit: String
}

/// Data container for point cloud binary data.
struct PointCloudFrameData {
    let bytes: Data
    let validSize: Int
    let pointCount: Int
}

/// Data container for mesh reconstruction binary data.
struct MeshFrameData {
    let bytes: Data
    let validSize: Int
    let anchorCount: Int
    let totalVertexCount: Int
    let totalFaceCount: Int
    /// World-space vertices (after applying anchor transforms). Nil for legacy binary-only path.
    let worldVertices: [(Double, Double, Double)]?
    /// Triangle indices referencing worldVertices. Nil for legacy binary-only path.
    let triangles: [(UInt32, UInt32, UInt32)]?
}

protocol DatasetWriter: AnyObject {
    func createSessionDirectory(baseDir: URL?) -> URL?
    func pauseWriters()
    func resumeWriters()
    func deleteSessionDirectory() -> Bool
    func initializeWriters() -> Bool
    func logSystem(message: String)
    func logError(message: String, error: Error?)
    func writePoseRow(timestamp: Int64, pose: [Float], trackingState: String)
    func writeTrackingState(timestampNs: Int64, state: UInt8, reason: UInt8, stateStr: String, reasonStr: String)
    func writeDeviceMetrics(
        timestampNs: Int64,
        batteryLevel: Float,
        batteryState: UInt8,
        batteryStateStr: String,
        cpuUsage: Float,
        memoryUsedMb: Double,
        memoryAvailableMb: Double,
        thermalState: UInt8,
        thermalStateStr: String
    )
    func writeImuSamples(samples: [ImuSample])
    func writeFrameLogRow(
        frameIndex: Int,
        globalArFrameIndex: Int,
        arkitTimestampNs: Int64,
        trackingState: String,
        encoded: Bool,
        depthAvailable: Bool,
        pointCloudAvailable: Bool,
        meshAvailable: Bool
    )
    func logTrackingStateTransition(previousState: String, nextState: String, timestampNs: Int64)
    func writePointCloud(timestamp: Int64, frameData: PointCloudFrameData?)
    func writeCompressedRgbFrame(timestamp: Int64, jpegData: Data)
    func writeDepthFrame(timestamp: Int64, frameData: DepthFrameData?) -> Bool
    func writeMeshFrame(timestamp: Int64, frameData: MeshFrameData?) -> Bool
    func writeIntrinsics(timestampNs: Int64, intrinsics: [String: Any])
    func writeDepthIntrinsics(timestampNs: Int64, intrinsics: [String: Any])
    func writeMetadata(metadata: [String: Any?]) -> Bool
    func writeSessionSummary(summaryText: String)
    func writeFrameDropLog(dropLog: [String: Any?]) -> String?
    func addVideoBytesWritten(videoBytes: Int64)
    func getVideoOutputPath() -> String?
    func getSessionDirectory() -> String?
    func getRecordingStats() -> [String: Any]
    func getFreeStorageBeforeBytes() -> Int64
    func getFreeStorageAfterBytes() -> Int64
    func getWriterAverageLatencyMs() -> Double
    func flushRealtimeData(timestampNs: Int64)
    /// Set the static camera→IMU extrinsic (rotation as row-major 9 doubles, translation
    /// in metres in the camera optical frame). Until called, no camera_link → imu_frame
    /// transform is emitted on /tf.
    func setCameraImuExtrinsic(rotationRowMajor: [Double], translationXYZ: (x: Double, y: Double, z: Double))
    func captureFreeStorageAfterSnapshot()
    func createSpatialDataZip() -> (Bool, String?, String?)
    func finalizeWriters()
    func release()
}
