import CryptoKit
import Foundation
import ImageIO
import UIKit
import simd

/// MCAP-based dataset writer that writes spatial data as ROS2-compatible MCAP messages.
/// Implements the same DatasetWriter protocol as DatasetWriterImpl, allowing seamless
/// swap via feature flag.
class MCAPDatasetWriter: DatasetWriter {

    private static let logFlushEveryNRows = 30
    private static let realtimeFlushIntervalNs: Int64 = 500_000_000
    private static let worldFrameId = "world"
    private static let cameraLinkFrameId = "camera_link"
    private static let cameraOpticalFrameId = "camera_optical_frame"
    private static let imuFrameId = "imu_frame"

    /// Cap the session thumbnail's long edge so it stays ≤1080p (1920×1080 for 16:9).
    /// The source RGB frame can be 4K; embedded as base64 in the assets API payload
    /// that overflows the request body limit, so downscale before writing to disk.
    private static let thumbnailMaxPixelSize = 1920
    private static let cameraLinkToOpticalRotation = (
        x: 1.0,
        y: 0.0,
        z: 0.0,
        w: 0.0
    )

    private let deviceModel: String
    private let iosVersion: String

    private var baseOutputDir: URL?
    private var sessionDir: URL?
    private var spatialDataDir: URL?

    // MCAP writer for spatial data
    private var mcapWriter: MCAPWriter?
    private var mcapFileURL: URL?

    // Text file handles (system log, frame log stay as text for debugging)
    private var frameLogHandle: FileHandle?
    private var systemLogHandle: FileHandle?

    private var isInitialized: Bool = false

    // Channel IDs
    private var poseChannelId: UInt16 = 0
    private var imuChannelId: UInt16 = 0
    private var compressedRgbChannelId: UInt16 = 0
    private var depthChannelId: UInt16 = 0
    private var pointCloudChannelId: UInt16 = 0
    private var meshChannelId: UInt16 = 0
    private var meshCloudChannelId: UInt16 = 0
    private var cameraInfoChannelId: UInt16 = 0
    private var depthCameraInfoChannelId: UInt16 = 0
    private var tfChannelId: UInt16 = 0
    private var cameraImuExtrinsicsChannelId: UInt16 = 0
    private var cameraImuExtrinsicWritten = false
    private var trajectoryChannelId: UInt16 = 0
    private var trackingStateChannelId: UInt16 = 0
    private var deviceMetricsChannelId: UInt16 = 0
    private var imuIntrinsicsChannelId: UInt16 = 0
    private var arkitImuChannelId: UInt16 = 0
    private var arkitImuIntrinsicsChannelId: UInt16 = 0

    // Cached IMU intrinsics & rate, populated when intrinsics are written so
    // per-sample covariance can be filled in without re-fetching.
    private var cachedImuIntrinsics: ImuIntrinsics?
    private var cachedImuRateHz: Int = 0
    private var cachedArkitImuIntrinsics: ImuIntrinsics?
    private var cachedArkitImuRateHz: Int = 0

    // Cached schema IDs reused across channel registrations.
    private var compressedImageSchemaIdCached: UInt16 = 0
    private var imageSchemaIdCached: UInt16 = 0
    private var camInfoSchemaIdCached: UInt16 = 0
    private var tfSchemaIdCached: UInt16 = 0
    private var imuSchemaIdCached: UInt16 = 0
    private var poseSchemaIdCached: UInt16 = 0

    // Counters
    private var poseCount: Int = 0
    private var imuSampleCount: Int = 0
    private var pointCloudCount: Int = 0
    private var depthFrameCountWriter: Int = 0
    private var meshFrameCountWriter: Int = 0
    private var frameLogRows: Int = 0
    private var skippedDepthFrames: Int = 0
    private var totalBytesWritten: Int64 = 0
    private var freeStorageBeforeBytes: Int64 = 0
    private var freeStorageAfterBytes: Int64 = 0
    private var writerLatencyTotalNs: Int64 = 0
    private var writerLatencySamples: Int64 = 0
    private var writersPaused: Bool = false
    private var lastRealtimeFlushTimestampNs: Int64 = 0

    // Trajectory accumulation for periodic Path snapshot
    private var trajectoryPoses: [(timestampNs: Int64, x: Float, y: Float, z: Float, qx: Float, qy: Float, qz: Float, qw: Float)] = []
    private var lastTrajectoryWriteLogTime: UInt64 = 0
    private static let trajectoryWriteIntervalNs: UInt64 = 5_000_000_000  // 5 seconds

    // Depth dimensions (for CameraInfo)
    private var depthWidth: Int = 0
    private var depthHeight: Int = 0
    private var intrinsicsJsonWritten: Bool = false
    private var thumbnailSaved: Bool = false


    init(deviceModel: String, iosVersion: String) {
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
    }

    // MARK: - Session Directory

    func createSessionDirectory(baseDir: URL?) -> URL? {
        do {
            let filesDir = baseDir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("ar_sessions")
            baseOutputDir = filesDir

            if !FileManager.default.fileExists(atPath: filesDir.path) {
                try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
            }
            BackupExclusion.exclude(filesDir)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let timestamp = formatter.string(from: Date())

            let session = filesDir.appendingPathComponent("session_\(timestamp)_\(UIDevice.current.modelSlug)")
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)

            sessionDir = session

            if let values = try? session.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let capacity = values.volumeAvailableCapacityForImportantUsage {
                freeStorageBeforeBytes = capacity
            }

            print("Session directory created: \(session.path)")
            return session
        } catch {
            print("Failed to create session directory: \(error.localizedDescription)")
            return nil
        }
    }

    func pauseWriters() {
        writersPaused = true
        mcapWriter?.forceFlushChunk()
        frameLogHandle?.synchronizeFile()
        systemLogHandle?.synchronizeFile()
    }

    func resumeWriters() {
        writersPaused = false
    }

    func deleteSessionDirectory() -> Bool {
        guard let directory = sessionDir else { return false }
        do {
            finalizeWriters()
            try FileManager.default.removeItem(at: directory)
            baseOutputDir = nil
            sessionDir = nil
            spatialDataDir = nil
            isInitialized = false
            return true
        } catch {
            print("Failed to delete session directory: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Initialize

    func initializeWriters() -> Bool {
        guard let session = sessionDir else { return false }
        do {
            // Initialize MCAP writer
            let sessionTimestamp = session.lastPathComponent.replacingOccurrences(of: "session_", with: "")
            let mcapURL = session.appendingPathComponent("session_data_\(sessionTimestamp).mcap")
            mcapFileURL = mcapURL
            let writer = MCAPWriter()
            guard writer.open(url: mcapURL, profile: "ros2", library: "fpv_labs/1.0") else {
                return false
            }
            mcapWriter = writer

            // Register schemas and channels
            registerSchemasAndChannels()

            isInitialized = true
            logSystem(message: "MCAP session log initialized")
            logSystem(message: "Device: \(deviceModel)")
            logSystem(message: "iOS: \(iosVersion)")
            return true
        } catch {
            print("Failed to initialize MCAP writers: \(error.localizedDescription)")
            return false
        }
    }

    private func registerSchemasAndChannels() {
        guard let writer = mcapWriter else { return }

        let enc = ROS2SchemaDefinitions.schemaEncoding
        let msgEnc = ROS2SchemaDefinitions.messageEncoding

        let poseSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.poseStampedName,
            encoding: enc,
            data: ROS2SchemaDefinitions.poseStampedSchema
        )
        poseSchemaIdCached = poseSchemaId
        poseChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.poseTopic,
            messageEncoding: msgEnc,
            schemaId: poseSchemaId
        )

        let imuSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.imuName,
            encoding: enc,
            data: ROS2SchemaDefinitions.imuSchema
        )
        imuSchemaIdCached = imuSchemaId
        imuChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.imuTopic,
            messageEncoding: msgEnc,
            schemaId: imuSchemaId
        )

        let imageSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.imageName,
            encoding: enc,
            data: ROS2SchemaDefinitions.imageSchema
        )
        imageSchemaIdCached = imageSchemaId
        depthChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.depthTopic,
            messageEncoding: msgEnc,
            schemaId: imageSchemaId
        )

        let compressedImageSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.compressedImageName,
            encoding: enc,
            data: ROS2SchemaDefinitions.compressedImageSchema
        )
        compressedImageSchemaIdCached = compressedImageSchemaId
        compressedRgbChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.compressedRgbTopic,
            messageEncoding: msgEnc,
            schemaId: compressedImageSchemaId
        )

        let pc2SchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.pointCloud2Name,
            encoding: enc,
            data: ROS2SchemaDefinitions.pointCloud2Schema
        )
        pointCloudChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.pointCloudTopic,
            messageEncoding: msgEnc,
            schemaId: pc2SchemaId
        )

        let markerSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.markerName,
            encoding: enc,
            data: ROS2SchemaDefinitions.markerSchema
        )
        meshChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.meshTopic,
            messageEncoding: msgEnc,
            schemaId: markerSchemaId
        )

        // mesh_cloud reuses PointCloud2 schema
        meshCloudChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.meshCloudTopic,
            messageEncoding: msgEnc,
            schemaId: pc2SchemaId
        )

        let camInfoSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.cameraInfoName,
            encoding: enc,
            data: ROS2SchemaDefinitions.cameraInfoSchema
        )
        camInfoSchemaIdCached = camInfoSchemaId
        cameraInfoChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.cameraInfoTopic,
            messageEncoding: msgEnc,
            schemaId: camInfoSchemaId
        )
        depthCameraInfoChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.depthCameraInfoTopic,
            messageEncoding: msgEnc,
            schemaId: camInfoSchemaId
        )

        let tfSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.tfMessageName,
            encoding: enc,
            data: ROS2SchemaDefinitions.tfMessageSchema
        )
        tfSchemaIdCached = tfSchemaId
        tfChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.tfTopic,
            messageEncoding: msgEnc,
            schemaId: tfSchemaId
        )
        cameraImuExtrinsicsChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.cameraImuExtrinsicsTopic,
            messageEncoding: msgEnc,
            schemaId: tfSchemaId
        )

        let pathSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.pathName,
            encoding: enc,
            data: ROS2SchemaDefinitions.pathSchema
        )
        trajectoryChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.trajectoryTopic,
            messageEncoding: msgEnc,
            schemaId: pathSchemaId
        )

        let trackingStateSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.trackingStateName,
            encoding: enc,
            data: ROS2SchemaDefinitions.trackingStateSchema
        )
        trackingStateChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.trackingStateTopic,
            messageEncoding: msgEnc,
            schemaId: trackingStateSchemaId
        )

        let deviceMetricsSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.deviceMetricsName,
            encoding: enc,
            data: ROS2SchemaDefinitions.deviceMetricsSchema
        )
        deviceMetricsChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.deviceMetricsTopic,
            messageEncoding: msgEnc,
            schemaId: deviceMetricsSchemaId
        )

        let imuIntrinsicsSchemaId = writer.addSchema(
            name: ROS2SchemaDefinitions.imuIntrinsicsName,
            encoding: enc,
            data: ROS2SchemaDefinitions.imuIntrinsicsSchema
        )
        imuIntrinsicsChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.imuIntrinsicsTopic,
            messageEncoding: msgEnc,
            schemaId: imuIntrinsicsSchemaId
        )

        // /arkit/imu and /arkit/imu/intrinsics reuse the schemas already
        // registered for /device/imu and /device/imu/intrinsics so downstream
        // tooling treats them as standard ROS Imu messages.
        arkitImuChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.arkitImuTopic,
            messageEncoding: msgEnc,
            schemaId: imuSchemaId
        )
        arkitImuIntrinsicsChannelId = writer.addChannel(
            topic: ROS2SchemaDefinitions.arkitImuIntrinsicsTopic,
            messageEncoding: msgEnc,
            schemaId: imuIntrinsicsSchemaId
        )
    }

    // MARK: - ARKit IMU

    /// Writes a single `/arkit/imu/intrinsics` message and caches the values so
    /// subsequent `/arkit/imu` sample writes can fill in gyro covariance.
    func writeArkitImuIntrinsics(timestampNs: Int64, intrinsics: ImuIntrinsics, sampleRateHz: Int) {
        guard isInitialized else { return }
        cachedArkitImuIntrinsics = intrinsics
        cachedArkitImuRateHz = sampleRateHz
        let data = CDRSerializer.serializeImuIntrinsics(
            timestampNs: timestampNs,
            frameId: Self.cameraLinkFrameId,
            intrinsics: intrinsics,
            sampleRateHz: UInt32(max(0, sampleRateHz))
        )
        let logTime = UInt64(bitPattern: timestampNs)
        mcapWriter?.addMessage(channelId: arkitImuIntrinsicsChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)
        logSystem(message: "ARKit IMU intrinsics written (source=\(intrinsics.source), sampleRateHz=\(sampleRateHz))")
    }

    /// Writes a single `/arkit/imu` sample with orientation from ARKit's
    /// VIO-fused pose and finite-difference angular velocity. Linear
    /// acceleration is not provided (covariance[0] = -1).
    func writeArkitImuSample(
        timestampNs: Int64,
        orientation: (x: Double, y: Double, z: Double, w: Double),
        angularVelocity: (x: Double, y: Double, z: Double)
    ) {
        guard isInitialized, !writersPaused else { return }
        let gyroVar = cachedArkitImuIntrinsics?.gyroVariance(sampleRateHz: cachedArkitImuRateHz)
        // ARKit's VIO orientation is good to ~1° drift over short windows.
        // Encode that as a per-axis variance of (1° in rad)² on the orientation
        // covariance diagonal.
        let oneDegRad = Double.pi / 180.0
        let orientationVar = oneDegRad * oneDegRad
        let data = CDRSerializer.serializeImu(
            timestampNs: timestampNs,
            frameId: Self.cameraLinkFrameId,
            orientation: orientation,
            angularVelocity: angularVelocity,
            linearAcceleration: nil,
            orientationVariance: orientationVar,
            angularVelocityVariance: gyroVar,
            linearAccelerationVariance: nil
        )
        let logTime = UInt64(bitPattern: timestampNs)
        mcapWriter?.addMessage(channelId: arkitImuChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)
    }

    // MARK: - IMU Intrinsics

    /// Writes a single `/device/imu/intrinsics` message and caches the values
    /// so subsequent IMU sample writes can fill in the covariance fields.
    func writeImuIntrinsics(timestampNs: Int64, intrinsics: ImuIntrinsics, sampleRateHz: Int) {
        guard isInitialized else { return }
        cachedImuIntrinsics = intrinsics
        cachedImuRateHz = sampleRateHz
        let data = CDRSerializer.serializeImuIntrinsics(
            timestampNs: timestampNs,
            frameId: Self.imuFrameId,
            intrinsics: intrinsics,
            sampleRateHz: UInt32(max(0, sampleRateHz))
        )
        let logTime = UInt64(bitPattern: timestampNs)
        mcapWriter?.addMessage(channelId: imuIntrinsicsChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)
        logSystem(message: "IMU intrinsics written (source=\(intrinsics.source), sampleRateHz=\(sampleRateHz))")
    }

    // MARK: - Logging

    func logSystem(message: String) {
        if !isInitialized || writersPaused { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        writeToHandle(systemLogHandle, line)
        totalBytesWritten += Int64(line.utf8.count)
    }

    func logError(message: String, error: Error?) {
        let suffix = error.map { ": \($0.localizedDescription)" } ?? ""
        logSystem(message: "ERROR: \(message)\(suffix)")
    }

    // MARK: - Pose

    func writePoseRow(timestamp: Int64, pose: [Float], trackingState: String) {
        if !isInitialized || writersPaused { return }
        let startNs = currentTimeNs()
        guard pose.count >= 7 else { return }

        let data = CDRSerializer.serializePoseStamped(
            timestampNs: timestamp,
            frameId: Self.worldFrameId,
            position: (x: pose[0], y: pose[1], z: pose[2]),
            orientation: (x: pose[3], y: pose[4], z: pose[5], w: pose[6])
        )

        let logTime = UInt64(bitPattern: timestamp)
        mcapWriter?.addMessage(channelId: poseChannelId, logTime: logTime, publishTime: logTime, data: data)
        poseCount += 1
        totalBytesWritten += Int64(data.count + 22) // message overhead

        // Write per-frame TF (world -> camera_link -> camera_optical_frame).
        // The static camera_link -> imu_frame extrinsic lives on its own one-shot topic
        // (`/device/camera_imu_extrinsics`) so it isn't repeated every frame.
        let tfData = CDRSerializer.serializeTFMessage(
            timestampNs: timestamp,
            transforms: [
                CDRSerializer.TFTransform(
                    frameId: Self.worldFrameId,
                    childFrameId: Self.cameraLinkFrameId,
                    translation: (x: Double(pose[0]), y: Double(pose[1]), z: Double(pose[2])),
                    rotation: (x: Double(pose[3]), y: Double(pose[4]), z: Double(pose[5]), w: Double(pose[6]))
                ),
                CDRSerializer.TFTransform(
                    frameId: Self.cameraLinkFrameId,
                    childFrameId: Self.cameraOpticalFrameId,
                    translation: (x: 0.0, y: 0.0, z: 0.0),
                    rotation: Self.cameraLinkToOpticalRotation
                )
            ]
        )
        mcapWriter?.addMessage(channelId: tfChannelId, logTime: logTime, publishTime: logTime, data: tfData)
        totalBytesWritten += Int64(tfData.count + 22)

        // Accumulate pose for trajectory and write periodic snapshot
        trajectoryPoses.append((timestampNs: timestamp, x: pose[0], y: pose[1], z: pose[2], qx: pose[3], qy: pose[4], qz: pose[5], qw: pose[6]))

        if logTime - lastTrajectoryWriteLogTime >= Self.trajectoryWriteIntervalNs {
            lastTrajectoryWriteLogTime = logTime
            let pathData = CDRSerializer.serializePath(
                timestampNs: timestamp,
                frameId: Self.worldFrameId,
                poses: trajectoryPoses
            )
            mcapWriter?.addMessage(channelId: trajectoryChannelId, logTime: logTime, publishTime: logTime, data: pathData)
            totalBytesWritten += Int64(pathData.count + 22)
            print("[Trajectory] Snapshot written: \(trajectoryPoses.count) poses, \(pathData.count) bytes")
            trajectoryPoses.removeAll(keepingCapacity: true)
        }

        recordWriterLatency(startNs: startNs)
    }

    // MARK: - Tracking State

    func writeTrackingState(timestampNs: Int64, state: UInt8, reason: UInt8, stateStr: String, reasonStr: String) {
        if !isInitialized || writersPaused { return }
        let logTime = UInt64(bitPattern: timestampNs)
        let data = CDRSerializer.serializeTrackingState(
            timestampNs: timestampNs,
            frameId: Self.cameraLinkFrameId,
            state: state,
            reason: reason,
            stateStr: stateStr,
            reasonStr: reasonStr
        )
        mcapWriter?.addMessage(channelId: trackingStateChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)
    }

    // MARK: - Device Metrics

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
    ) {
        if !isInitialized || writersPaused { return }
        let logTime = UInt64(bitPattern: timestampNs)
        let data = CDRSerializer.serializeDeviceMetrics(
            timestampNs: timestampNs,
            frameId: "device",
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            batteryStateStr: batteryStateStr,
            cpuUsage: cpuUsage,
            memoryUsedMb: memoryUsedMb,
            memoryAvailableMb: memoryAvailableMb,
            thermalState: thermalState,
            thermalStateStr: thermalStateStr,
            deviceModel: deviceModel
        )
        mcapWriter?.addMessage(channelId: deviceMetricsChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)
    }

    // MARK: - IMU

    func writeImuSamples(samples: [ImuSample]) {
        if !isInitialized || writersPaused || samples.isEmpty { return }
        let startNs = currentTimeNs()

        let accelVar = cachedImuIntrinsics?.accelVariance(sampleRateHz: cachedImuRateHz)
        let gyroVar = cachedImuIntrinsics?.gyroVariance(sampleRateHz: cachedImuRateHz)

        // CMDeviceMotion's fused attitude is good to roughly 2° over short
        // windows; encode that as (2° in rad)² on the orientation covariance
        // diagonal — same convention as /arkit/imu's (1° in rad)².
        let twoDegRad = 2.0 * Double.pi / 180.0
        let attitudeVariance = twoDegRad * twoDegRad

        for sample in samples {
            let logTime = UInt64(bitPattern: sample.timestampNs)
            let orientation: (x: Double, y: Double, z: Double, w: Double)? = sample.attitude.map {
                (x: Double($0.imag.x), y: Double($0.imag.y), z: Double($0.imag.z), w: Double($0.real))
            }
            let data = CDRSerializer.serializeImu(
                timestampNs: sample.timestampNs,
                frameId: Self.imuFrameId,
                orientation: orientation,
                angularVelocity: (x: Double(sample.gyroX), y: Double(sample.gyroY), z: Double(sample.gyroZ)),
                linearAcceleration: (x: Double(sample.accelX), y: Double(sample.accelY), z: Double(sample.accelZ)),
                orientationVariance: orientation == nil ? nil : attitudeVariance,
                angularVelocityVariance: gyroVar,
                linearAccelerationVariance: accelVar
            )
            mcapWriter?.addMessage(channelId: imuChannelId, logTime: logTime, publishTime: logTime, data: data)
            imuSampleCount += 1
            totalBytesWritten += Int64(data.count + 22)
        }

        recordWriterLatency(startNs: startNs)
    }

    // MARK: - Camera↔IMU extrinsic

    /// Publish the estimated rigid offset between camera optical frame and IMU body frame
    /// as a single TFMessage on the dedicated `/device/camera_imu_extrinsics` topic.
    /// Idempotent within a session — first call wins; subsequent calls are ignored so
    /// downstream consumers see one canonical value per recording.
    func setCameraImuExtrinsic(rotationRowMajor R: [Double], translationXYZ t: (x: Double, y: Double, z: Double)) {
        guard isInitialized, R.count == 9 else { return }
        if cameraImuExtrinsicWritten { return }
        // R rotates a vector from the camera frame to the IMU frame.
        // TFTransform stores child-in-parent: parent=camera_link, child=imu_frame, so the
        // translation is the IMU position expressed in camera_link, and the rotation is
        // the orientation of imu_frame as seen from camera_link — i.e. R^T as a quat.
        let rt = [
            R[0], R[3], R[6],
            R[1], R[4], R[7],
            R[2], R[5], R[8]
        ]
        let q = Self.matrixToQuaternion(rt)
        let timestampNs = Int64(bitPattern: currentTimeNs())
        let data = CDRSerializer.serializeTFMessage(
            timestampNs: timestampNs,
            transforms: [
                CDRSerializer.TFTransform(
                    frameId: Self.cameraLinkFrameId,
                    childFrameId: Self.imuFrameId,
                    translation: t,
                    rotation: q
                )
            ]
        )
        let logTime = UInt64(bitPattern: timestampNs)
        mcapWriter?.addMessage(channelId: cameraImuExtrinsicsChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)
        cameraImuExtrinsicWritten = true
    }

    private static func matrixToQuaternion(_ m: [Double]) -> (x: Double, y: Double, z: Double, w: Double) {
        // Standard sign-stable matrix → quaternion. m is row-major.
        let tr = m[0] + m[4] + m[8]
        if tr > 0 {
            let s = sqrt(tr + 1.0) * 2.0
            return ((m[7] - m[5]) / s, (m[2] - m[6]) / s, (m[3] - m[1]) / s, 0.25 * s)
        } else if m[0] > m[4] && m[0] > m[8] {
            let s = sqrt(1.0 + m[0] - m[4] - m[8]) * 2.0
            return (0.25 * s, (m[1] + m[3]) / s, (m[2] + m[6]) / s, (m[7] - m[5]) / s)
        } else if m[4] > m[8] {
            let s = sqrt(1.0 + m[4] - m[0] - m[8]) * 2.0
            return ((m[1] + m[3]) / s, 0.25 * s, (m[5] + m[7]) / s, (m[2] - m[6]) / s)
        } else {
            let s = sqrt(1.0 + m[8] - m[0] - m[4]) * 2.0
            return ((m[2] + m[6]) / s, (m[5] + m[7]) / s, 0.25 * s, (m[3] - m[1]) / s)
        }
    }

    // MARK: - Frame Log

    func writeFrameLogRow(
        frameIndex: Int,
        globalArFrameIndex: Int,
        arkitTimestampNs: Int64,
        trackingState: String,
        encoded: Bool,
        depthAvailable: Bool,
        pointCloudAvailable: Bool,
        meshAvailable: Bool
    ) {
        if !isInitialized || writersPaused { return }
        let startNs = currentTimeNs()
        let line = "\(frameIndex),\(globalArFrameIndex),\(arkitTimestampNs),\(trackingState),\(encoded ? 1 : 0),\(depthAvailable ? 1 : 0),\(pointCloudAvailable ? 1 : 0),\(meshAvailable ? 1 : 0)\n"
        writeToHandle(frameLogHandle, line)
        frameLogRows += 1
        totalBytesWritten += Int64(line.utf8.count)
        if frameLogRows % Self.logFlushEveryNRows == 0 {
            frameLogHandle?.synchronizeFile()
            systemLogHandle?.synchronizeFile()
        }
        recordWriterLatency(startNs: startNs)
    }

    func logTrackingStateTransition(previousState: String, nextState: String, timestampNs: Int64) {
        logSystem(message: "Tracking state transition: \(previousState) -> \(nextState) at \(timestampNs) ns")
    }

    // MARK: - Thumbnail

    /// Downscale a full-size JPEG frame to a ≤1080p thumbnail (long edge capped at
    /// [thumbnailMaxPixelSize]) so it stays small on disk and when base64-embedded
    /// in the assets-registration payload. Returns the original bytes unchanged if
    /// decoding fails or the source is already smaller than the re-encoded result.
    private func makeThumbnailJpeg(from jpegData: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else { return jpegData }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let scaled = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
        else { return jpegData }
        return scaled.count < jpegData.count ? scaled : jpegData
    }

    // MARK: - Compressed RGB

    func writeCompressedRgbFrame(timestamp: Int64, jpegData: Data) {
        guard isInitialized, !writersPaused else { return }
        // Save first JPEG frame as thumbnail
        if !thumbnailSaved, let dir = sessionDir {
            let thumbnailURL = dir.appendingPathComponent("thumbnail.jpg")
            do {
                try makeThumbnailJpeg(from: jpegData).write(to: thumbnailURL)
                thumbnailSaved = true
                print("thumbnail.jpg saved in \(dir.path)")
            } catch {
                print("Failed to save thumbnail: \(error.localizedDescription)")
            }
        }
        let startNs = currentTimeNs()
        do {
            let data = CDRSerializer.serializeCompressedImage(
                timestampNs: timestamp,
                frameId: Self.cameraOpticalFrameId,
                format: "jpeg",
                imageData: jpegData
            )
            mcapWriter?.addMessage(channelId: compressedRgbChannelId, logTime: UInt64(timestamp), publishTime: UInt64(timestamp), data: data)
            totalBytesWritten += Int64(data.count + 22)
        } catch {
            logError(message: "Failed to write compressed RGB frame", error: error)
        }
        recordWriterLatency(startNs: startNs)
    }

    // MARK: - Point Cloud

    func writePointCloud(timestamp: Int64, frameData: PointCloudFrameData?) {
        guard isInitialized, let frameData = frameData else { return }
        let startNs = currentTimeNs()

        // The existing binary format has a 12-byte header: [int64 timestamp][int32 pointCount]
        // followed by point data (4 floats per point). Strip the header.
        let headerSize = 12
        guard frameData.validSize > headerSize else { return }
        let pointData = frameData.bytes.subdata(in: headerSize..<frameData.validSize)

        // Write per-frame point cloud to MCAP
        let data = CDRSerializer.serializePointCloud2(
            timestampNs: timestamp,
            frameId: Self.worldFrameId,
            pointCount: UInt32(frameData.pointCount),
            pointData: pointData
        )
        let logTime = UInt64(bitPattern: timestamp)
        mcapWriter?.addMessage(channelId: pointCloudChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)

        pointCloudCount += 1

        if frameData.pointCount <= 0 {
            logSystem(message: "WARN: point cloud frame \(timestamp) has no points")
        }
        recordWriterLatency(startNs: startNs)
    }

    // MARK: - Depth

    func writeDepthFrame(timestamp: Int64, frameData: DepthFrameData?) -> Bool {
        guard isInitialized, let frameData = frameData else { return false }
        let startNs = currentTimeNs()
        let expectedSize = frameData.width * frameData.height * frameData.bytesPerPixel
        if frameData.validSize != expectedSize {
            skippedDepthFrames += 1
            logSystem(message: "WARN: skipping depth frame \(timestamp), invalid size \(frameData.validSize), expected \(expectedSize)")
            return false
        }

        depthWidth = frameData.width
        depthHeight = frameData.height

        let data = CDRSerializer.serializeImage(
            timestampNs: timestamp,
            frameId: Self.cameraOpticalFrameId,
            height: UInt32(frameData.height),
            width: UInt32(frameData.width),
            encoding: "16UC1",
            isBigEndian: false,
            step: UInt32(frameData.width * frameData.bytesPerPixel),
            imageData: frameData.bytes.prefix(frameData.validSize)
        )

        let logTime = UInt64(bitPattern: timestamp)
        mcapWriter?.addMessage(channelId: depthChannelId, logTime: logTime, publishTime: logTime, data: data)
        depthFrameCountWriter += 1
        totalBytesWritten += Int64(data.count + 22)
        recordWriterLatency(startNs: startNs)
        return true
    }

    // MARK: - Mesh

    func writeMeshFrame(timestamp: Int64, frameData: MeshFrameData?) -> Bool {
        guard isInitialized, let frameData = frameData else { return false }
        let startNs = currentTimeNs()

        // Use pre-computed structured data from extractMeshData (avoids binary re-parsing)
        guard let vertices = frameData.worldVertices, let triangles = frameData.triangles else { return false }

        // Diagnostic: log mesh bounding box periodically
        if meshFrameCountWriter % 30 == 0 && !vertices.isEmpty {
            var minX = vertices[0].0, maxX = vertices[0].0
            var minY = vertices[0].1, maxY = vertices[0].1
            var minZ = vertices[0].2, maxZ = vertices[0].2
            for v in vertices {
                minX = min(minX, v.0); maxX = max(maxX, v.0)
                minY = min(minY, v.1); maxY = max(maxY, v.1)
                minZ = min(minZ, v.2); maxZ = max(maxZ, v.2)
            }
            print("[Mesh] verts=\(vertices.count) bbox x[\(String(format: "%.2f", minX)),\(String(format: "%.2f", maxX))] y[\(String(format: "%.2f", minY)),\(String(format: "%.2f", maxY))] z[\(String(format: "%.2f", minZ)),\(String(format: "%.2f", maxZ))]")
        }

        let logTime = UInt64(bitPattern: timestamp)

        // Write Marker (TRIANGLE_LIST)
        if !triangles.isEmpty {
            autoreleasepool {
                var markerPoints: [(Double, Double, Double)] = []
                markerPoints.reserveCapacity(triangles.count * 3)
                for tri in triangles {
                    let i0 = Int(tri.0), i1 = Int(tri.1), i2 = Int(tri.2)
                    if i0 < vertices.count && i1 < vertices.count && i2 < vertices.count {
                        markerPoints.append(vertices[i0])
                        markerPoints.append(vertices[i1])
                        markerPoints.append(vertices[i2])
                    }
                }
                let markerData = CDRSerializer.serializeMarker(
                    timestampNs: timestamp,
                    frameId: Self.worldFrameId,
                    points: markerPoints
                )
                mcapWriter?.addMessage(channelId: meshChannelId, logTime: logTime, publishTime: logTime, data: markerData)
                totalBytesWritten += Int64(markerData.count + 22)
            }
        }

        // Write mesh vertices as PointCloud2 on /map/mesh_cloud
        if !vertices.isEmpty {
            var pointData = Data(capacity: vertices.count * 16)
            for v in vertices {
                var fx = Float(v.0).bitPattern.littleEndian
                var fy = Float(v.1).bitPattern.littleEndian
                var fz = Float(v.2).bitPattern.littleEndian
                var fc = Float(1.0).bitPattern.littleEndian
                pointData.append(UnsafeBufferPointer(start: &fx, count: 1))
                pointData.append(UnsafeBufferPointer(start: &fy, count: 1))
                pointData.append(UnsafeBufferPointer(start: &fz, count: 1))
                pointData.append(UnsafeBufferPointer(start: &fc, count: 1))
            }
            let cloudData = CDRSerializer.serializePointCloud2(
                timestampNs: timestamp,
                frameId: Self.worldFrameId,
                pointCount: UInt32(vertices.count),
                pointData: pointData
            )
            mcapWriter?.addMessage(channelId: meshCloudChannelId, logTime: logTime, publishTime: logTime, data: cloudData)
            totalBytesWritten += Int64(cloudData.count + 22)
        }

        meshFrameCountWriter += 1
        recordWriterLatency(startNs: startNs)
        return true
    }

    // MARK: - Intrinsics

    func writeIntrinsics(timestampNs: Int64, intrinsics: [String: Any]) {
        if !isInitialized { return }

        let fx = (intrinsics["focalLengthX"] as? NSNumber)?.doubleValue ?? 0
        let fy = (intrinsics["focalLengthY"] as? NSNumber)?.doubleValue ?? 0
        let cx = (intrinsics["principalPointX"] as? NSNumber)?.doubleValue ?? 0
        let cy = (intrinsics["principalPointY"] as? NSNumber)?.doubleValue ?? 0
        let w = (intrinsics["imageWidth"] as? NSNumber)?.uint32Value ?? 0
        let h = (intrinsics["imageHeight"] as? NSNumber)?.uint32Value ?? 0

        let logTime = UInt64(bitPattern: timestampNs)
        let data = CDRSerializer.serializeCameraInfo(
            timestampNs: timestampNs,
            frameId: Self.cameraOpticalFrameId,
            height: h,
            width: w,
            fx: fx,
            fy: fy,
            cx: cx,
            cy: cy
        )
        mcapWriter?.addMessage(channelId: cameraInfoChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)

        intrinsicsJsonWritten = true
    }

    func writeDepthIntrinsics(timestampNs: Int64, intrinsics: [String: Any]) {
        if !isInitialized { return }

        let fx = (intrinsics["focalLengthX"] as? NSNumber)?.doubleValue ?? 0
        let fy = (intrinsics["focalLengthY"] as? NSNumber)?.doubleValue ?? 0
        let cx = (intrinsics["principalPointX"] as? NSNumber)?.doubleValue ?? 0
        let cy = (intrinsics["principalPointY"] as? NSNumber)?.doubleValue ?? 0
        let w = (intrinsics["imageWidth"] as? NSNumber)?.uint32Value ?? 0
        let h = (intrinsics["imageHeight"] as? NSNumber)?.uint32Value ?? 0

        let logTime = UInt64(bitPattern: timestampNs)
        let data = CDRSerializer.serializeCameraInfo(
            timestampNs: timestampNs,
            frameId: Self.cameraOpticalFrameId,
            height: h,
            width: w,
            fx: fx,
            fy: fy,
            cx: cx,
            cy: cy
        )
        mcapWriter?.addMessage(channelId: depthCameraInfoChannelId, logTime: logTime, publishTime: logTime, data: data)
        totalBytesWritten += Int64(data.count + 22)
    }

    // MARK: - Metadata

    @discardableResult
    func writeMetadata(metadata: [String: Any?]) -> Bool {
        if !isInitialized { return false }

        // Write as MCAP metadata record
        var flat: [String: String] = [:]
        flattenMetadata(metadata, prefix: "", into: &flat)
        mcapWriter?.addMetadata(name: "session_metadata", metadata: flat)

        // Write JSON to session root
        guard let session = sessionDir else { return false }

        // Strategy 1: Custom pretty-print serializer
        do {
            let json = toJsonValue(metadata, level: 0)
            let file = session.appendingPathComponent("metadata.json")
            try json.write(to: file, atomically: true, encoding: .utf8)
            totalBytesWritten += Int64(json.utf8.count)
            logSystem(message: "metadata.json written")
            return true
        } catch {
            logError(message: "metadata.json write failed (toJsonValue): \(error.localizedDescription)", error: error)
        }

        // Strategy 2: JSONSerialization fallback (lower peak memory)
        do {
            let sanitized = sanitizeForJsonSerialization(metadata)
            let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
            let file = session.appendingPathComponent("metadata.json")
            try data.write(to: file, options: .atomic)
            totalBytesWritten += Int64(data.count)
            logSystem(message: "metadata.json written (JSONSerialization fallback)")
            return true
        } catch {
            logError(message: "metadata.json write failed (JSONSerialization): \(error.localizedDescription)", error: error)
        }

        // Strategy 3: Minimal essential-only metadata
        do {
            let minimal = extractMinimalMetadata(from: metadata)
            let data = try JSONSerialization.data(withJSONObject: minimal, options: [])
            let file = session.appendingPathComponent("metadata.json")
            try data.write(to: file, options: .atomic)
            totalBytesWritten += Int64(data.count)
            logSystem(message: "metadata.json written (minimal fallback)")
            return true
        } catch {
            logError(message: "metadata.json write failed (minimal fallback): \(error.localizedDescription)", error: error)
        }

        return false
    }

    private func sanitizeForJsonSerialization(_ value: Any?) -> Any {
        switch value {
        case nil:
            return NSNull()
        case let dict as [String: Any?]:
            var out = [String: Any]()
            for (k, v) in dict {
                out[k] = sanitizeForJsonSerialization(v)
            }
            return out
        case let arr as [Any?]:
            return arr.map { sanitizeForJsonSerialization($0) }
        case let arr as [Any]:
            return arr.map { sanitizeForJsonSerialization($0) }
        default:
            return value!
        }
    }

    private func extractMinimalMetadata(from metadata: [String: Any?]) -> [String: Any] {
        var minimal: [String: Any] = [
            "metadata_fallback": true
        ]
        let essentialKeys: [String] = [
            "session_duration_seconds", "durationSeconds",
            "total_video_frames_encoded", "framesRecorded",
            "total_imu_samples", "imuSamples",
            "device_model", "ios_version",
            "resolution", "fps"
        ]
        for key in essentialKeys {
            if let val = metadata[key] {
                minimal[key] = val ?? NSNull()
            }
        }
        return minimal
    }

    func writeSessionSummary(summaryText: String) {
        if !isInitialized { return }
        guard let dataDir = spatialDataDir else { return }
        let file = dataDir.appendingPathComponent("session_summary.txt")
        try? summaryText.write(to: file, atomically: true, encoding: .utf8)
        totalBytesWritten += Int64(summaryText.utf8.count)
        logSystem(message: "session_summary.txt written")
    }

    func writeFrameDropLog(dropLog: [String: Any?]) -> String? {
        if !isInitialized { return nil }
        guard let dataDir = spatialDataDir else { return nil }
        let json = toJsonValue(dropLog, level: 0)
        let file = dataDir.appendingPathComponent("frame_drop_log.json")
        do {
            try json.write(to: file, atomically: true, encoding: .utf8)
            totalBytesWritten += Int64(json.utf8.count)
            logSystem(message: "frame_drop_log.json written")
            return file.lastPathComponent
        } catch {
            logError(message: "Failed to write frame_drop_log.json", error: error)
            return nil
        }
    }

    // MARK: - Stats / Storage

    func addVideoBytesWritten(videoBytes: Int64) {
        if videoBytes > 0 {
            totalBytesWritten += videoBytes
        }
    }

    func getVideoOutputPath() -> String? {
        return nil
    }

    func getSessionDirectory() -> String? {
        return sessionDir?.path
    }

    func getRecordingStats() -> [String: Any] {
        var mcapDurationMs: Int64 = 0
        if let start = mcapWriter?.getMessageStartTimeNs(),
           let end = mcapWriter?.getMessageEndTimeNs(),
           end > start {
            mcapDurationMs = Int64((end - start) / 1_000_000)
        }

        return [
            "poseCount": poseCount,
            "imuSampleCount": imuSampleCount,
            "pointCloudCount": pointCloudCount,
            "depthFrameCount": depthFrameCountWriter,
            "meshFrameCount": meshFrameCountWriter,
            "skippedDepthFrames": skippedDepthFrames,
            "totalBytesWritten": totalBytesWritten,
            "mcapDurationMs": mcapDurationMs
        ]
    }

    func getFreeStorageBeforeBytes() -> Int64 { freeStorageBeforeBytes }
    func getFreeStorageAfterBytes() -> Int64 { freeStorageAfterBytes }

    func getWriterAverageLatencyMs() -> Double {
        if writerLatencySamples <= 0 { return 0.0 }
        return (Double(writerLatencyTotalNs) / Double(writerLatencySamples)) / 1_000_000.0
    }

    func flushRealtimeData(timestampNs: Int64) {
        if !isInitialized || writersPaused { return }
        if timestampNs - lastRealtimeFlushTimestampNs < Self.realtimeFlushIntervalNs { return }
        lastRealtimeFlushTimestampNs = timestampNs
        mcapWriter?.forceFlushChunk()
        frameLogHandle?.synchronizeFile()
        systemLogHandle?.synchronizeFile()
    }

    func captureFreeStorageAfterSnapshot() {
        if let session = sessionDir,
           let values = try? session.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            freeStorageAfterBytes = capacity
        }
    }

    // MARK: - Finalization

    func createSpatialDataZip() -> (Bool, String?, String?) {
        guard let session = sessionDir, let mcapURL = mcapFileURL else {
            return (false, nil, "sessionDir or mcapFileURL is nil")
        }

        // Flush text writers
        closeHandle(&frameLogHandle)
        closeHandle(&systemLogHandle)

        // Finalize MCAP
        print("MCAPDatasetWriter: finishing MCAP writer (bytesWritten=\(mcapWriter?.bytesWritten ?? 0))")
        let finishStart = CFAbsoluteTimeGetCurrent()
        mcapWriter?.finish()
        mcapWriter = nil
        let finishElapsed = CFAbsoluteTimeGetCurrent() - finishStart
        print("MCAPDatasetWriter: mcapWriter.finish() done in \(String(format: "%.2f", finishElapsed))s")

        guard FileManager.default.fileExists(atPath: mcapURL.path) else {
            return (false, nil, "session_data.mcap missing after finalization")
        }

        print("MCAPDatasetWriter: session finalized at \(session.path)")
        return (true, session.path, nil)
    }

    func finalizeWriters() {
        closeHandle(&frameLogHandle)
        closeHandle(&systemLogHandle)
        if mcapWriter != nil {
            mcapWriter?.finish()
            mcapWriter = nil
        }
        captureFreeStorageAfterSnapshot()
        isInitialized = false
        print("MCAP dataset writers finalized")
    }

    func release() {
        finalizeWriters()
        baseOutputDir = nil
        sessionDir = nil
        spatialDataDir = nil
        poseCount = 0
        imuSampleCount = 0
        pointCloudCount = 0
        depthFrameCountWriter = 0
        meshFrameCountWriter = 0
        frameLogRows = 0
        skippedDepthFrames = 0
        totalBytesWritten = 0
        freeStorageBeforeBytes = 0
        freeStorageAfterBytes = 0
        writerLatencyTotalNs = 0
        writerLatencySamples = 0
        writersPaused = false
        lastRealtimeFlushTimestampNs = 0
        trajectoryPoses.removeAll()
        lastTrajectoryWriteLogTime = 0
        intrinsicsJsonWritten = false
        thumbnailSaved = false
        cachedImuIntrinsics = nil
        cachedImuRateHz = 0
        cachedArkitImuIntrinsics = nil
        cachedArkitImuRateHz = 0
        mcapWriter = nil
        mcapFileURL = nil
        compressedImageSchemaIdCached = 0
        imageSchemaIdCached = 0
        camInfoSchemaIdCached = 0
        tfSchemaIdCached = 0
        imuSchemaIdCached = 0
        print("MCAP dataset writer released")
    }

    // MARK: - End-of-Session Writes (no-op: all data is now written per-frame)

    private func writeEndOfSessionMessages() {
        // All data (poses, point clouds, mesh) is now written per-frame during recording.
        // This method is kept as a no-op for protocol/caller compatibility.
    }

    // MARK: - Private Helpers

    private func writeToHandle(_ handle: FileHandle?, _ string: String) {
        guard let handle = handle, let data = string.data(using: .utf8) else { return }
        handle.write(data)
    }

    private func closeHandle(_ handle: inout FileHandle?) {
        handle?.synchronizeFile()
        handle?.closeFile()
        handle = nil
    }

    private func currentTimeNs() -> UInt64 {
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    private func recordWriterLatency(startNs: UInt64) {
        let elapsedNs = Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - startNs)
        if elapsedNs > 0 {
            writerLatencyTotalNs += elapsedNs
            writerLatencySamples += 1
        }
    }

    /// Converts a 3x3 rotation matrix to a quaternion (x, y, z, w).
    private func quaternionFrom3x3(
        m00: Float, m01: Float, m02: Float,
        m10: Float, m11: Float, m12: Float,
        m20: Float, m21: Float, m22: Float
    ) -> (x: Double, y: Double, z: Double, w: Double) {
        let trace = m00 + m11 + m22
        let x, y, z, w: Double
        if trace > 0 {
            let s = 0.5 / sqrt(Double(trace + 1.0))
            w = 0.25 / s
            x = Double(m21 - m12) * s
            y = Double(m02 - m20) * s
            z = Double(m10 - m01) * s
        } else if m00 > m11 && m00 > m22 {
            let s = 2.0 * sqrt(Double(1.0 + m00 - m11 - m22))
            w = Double(m21 - m12) / s
            x = 0.25 * s
            y = Double(m01 + m10) / s
            z = Double(m02 + m20) / s
        } else if m11 > m22 {
            let s = 2.0 * sqrt(Double(1.0 + m11 - m00 - m22))
            w = Double(m02 - m20) / s
            x = Double(m01 + m10) / s
            y = 0.25 * s
            z = Double(m12 + m21) / s
        } else {
            let s = 2.0 * sqrt(Double(1.0 + m22 - m00 - m11))
            w = Double(m10 - m01) / s
            x = Double(m02 + m20) / s
            y = Double(m12 + m21) / s
            z = 0.25 * s
        }
        return (x: x, y: y, z: z, w: w)
    }

    /// Flattens a nested dictionary to dot-separated keys for MCAP metadata.
    private func flattenMetadata(_ dict: [String: Any?], prefix: String, into result: inout [String: String]) {
        for (key, value) in dict {
            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any?] {
                flattenMetadata(nested, prefix: fullKey, into: &result)
            } else if let value = value {
                result[fullKey] = "\(value)"
            } else {
                result[fullKey] = "null"
            }
        }
    }

    // MARK: - JSON Serialization (for backward-compatible files)

    private func toJsonValue(_ value: Any?, level: Int) -> String {
        switch value {
        case nil:
            return "null"
        case let s as String:
            return "\"\(escapeJson(s))\""
        case let n as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                return n.boolValue ? "true" : "false"
            }
            return "\(n)"
        case let b as Bool:
            return b ? "true" : "false"
        case let i as Int:
            return "\(i)"
        case let i as Int64:
            return "\(i)"
        case let d as Double:
            return "\(d)"
        case let f as Float:
            return "\(f)"
        case let dict as [String: Any?]:
            if dict.isEmpty { return "{}" }
            let indent = String(repeating: "  ", count: level)
            let childIndent = String(repeating: "  ", count: level + 1)
            let entries = dict.sorted(by: { $0.key < $1.key }).map { key, val_ in
                "\(childIndent)\"\(escapeJson(key))\": \(toJsonValue(val_, level: level + 1))"
            }.joined(separator: ",\n")
            return "{\n\(entries)\n\(indent)}"
        case let arr as [Any?]:
            if arr.isEmpty { return "[]" }
            let indent = String(repeating: "  ", count: level)
            let childIndent = String(repeating: "  ", count: level + 1)
            let entries = arr.map { item in
                "\(childIndent)\(toJsonValue(item, level: level + 1))"
            }.joined(separator: ",\n")
            return "[\n\(entries)\n\(indent)]"
        case let arr as [Any]:
            if arr.isEmpty { return "[]" }
            let indent = String(repeating: "  ", count: level)
            let childIndent = String(repeating: "  ", count: level + 1)
            let entries = arr.map { item in
                "\(childIndent)\(toJsonValue(item, level: level + 1))"
            }.joined(separator: ",\n")
            return "[\n\(entries)\n\(indent)]"
        default:
            return "\"\(escapeJson(String(describing: value!)))\""
        }
    }

    private func escapeJson(_ raw: String) -> String {
        return raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Data Reading Helpers

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func readFloat32(at offset: Int) -> Float {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            Float(bitPattern: ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian)
        }
    }

    func readFloat32Array(at offset: Int, count: Int) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            result.append(readFloat32(at: offset + i * 4))
        }
        return result
    }
}
