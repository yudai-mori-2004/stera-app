import Foundation
import UIKit
import zlib

/// Writes AR recording data to files: video, CSVs, JSON, and binary pointcloud/depth payloads.
class DatasetWriterImpl: DatasetWriter {

    private static let logFlushEveryNRows = 30

    private let deviceModel: String
    private let iosVersion: String

    private var baseOutputDir: URL?
    private var sessionDir: URL?
    private var spatialDataDir: URL?

    private var posesHandle: FileHandle?
    private var imuHandle: FileHandle?
    private var frameLogHandle: FileHandle?
    private var systemLogHandle: FileHandle?

    private var isInitialized: Bool = false

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
    private var depthFormatWritten: Bool = false
    private var pointcloudFormatWritten: Bool = false
    private var meshFormatWritten: Bool = false
    private var writerLatencyTotalNs: Int64 = 0
    private var writerLatencySamples: Int64 = 0
    private var writersPaused: Bool = false

    // Zip archive built incrementally
    private var zipFileURL: URL?
    private var zipArchive: ZipArchiveWriter?

    init(deviceModel: String, iosVersion: String) {
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
    }

    func createSessionDirectory(baseDir: URL?) -> URL? {
        do {
            let filesDir =
                baseDir
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ar_sessions")
            baseOutputDir = filesDir

            if !FileManager.default.fileExists(atPath: filesDir.path) {
                try FileManager.default.createDirectory(
                    at: filesDir, withIntermediateDirectories: true)
            }
            BackupExclusion.exclude(filesDir)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let timestamp = formatter.string(from: Date())

            let session = filesDir.appendingPathComponent("session_\(timestamp)_\(UIDevice.current.modelSlug)")
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)

            let spatialData = session.appendingPathComponent("spatial_data")
            try FileManager.default.createDirectory(
                at: spatialData, withIntermediateDirectories: true)

            sessionDir = session
            spatialDataDir = spatialData

            if let values = try? session.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]),
                let capacity = values.volumeAvailableCapacityForImportantUsage
            {
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
        posesHandle?.synchronizeFile()
        imuHandle?.synchronizeFile()
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

    func initializeWriters() -> Bool {
        guard let dataDir = spatialDataDir else { return false }
        do {
            // Poses CSV
            let posesFile = dataDir.appendingPathComponent("poses.csv")
            FileManager.default.createFile(atPath: posesFile.path, contents: nil)
            posesHandle = try FileHandle(forWritingTo: posesFile)
            writeToHandle(posesHandle, "timestamp_ns,tx,ty,tz,qx,qy,qz,qw,tracking_state\n")

            // IMU CSV
            let imuFile = dataDir.appendingPathComponent("imu.csv")
            FileManager.default.createFile(atPath: imuFile.path, contents: nil)
            imuHandle = try FileHandle(forWritingTo: imuFile)
            writeToHandle(imuHandle, "timestamp_ns,sensor_type,x,y,z,accuracy\n")

            // Frame log CSV
            let frameLogFile = dataDir.appendingPathComponent("frame_log.csv")
            FileManager.default.createFile(atPath: frameLogFile.path, contents: nil)
            frameLogHandle = try FileHandle(forWritingTo: frameLogFile)
            writeToHandle(
                frameLogHandle,
                "frame_index,global_ar_frame_index,arkit_timestamp_ns,tracking_state,encoded,depth_available,pointcloud_available,mesh_available\n"
            )

            // System log
            let sysLogFile = dataDir.appendingPathComponent("system_log.txt")
            FileManager.default.createFile(atPath: sysLogFile.path, contents: nil)
            systemLogHandle = try FileHandle(forWritingTo: sysLogFile)
            writeToHandle(
                systemLogHandle,
                "FPV Labs AR Recorder System Log\n================================\n")

            // Initialize zip
            guard let session = sessionDir else { return false }
            let sessionTimestamp = session.lastPathComponent.replacingOccurrences(
                of: "session_", with: "")
            let zipURL = session.appendingPathComponent("session_data_\(sessionTimestamp).zip")
            zipFileURL = zipURL
            zipArchive = ZipArchiveWriter(url: zipURL)

            writePointCloudFormatIfNeeded()

            isInitialized = true
            logSystem(message: "Session log initialized")
            logSystem(message: "Device: \(deviceModel)")
            logSystem(message: "iOS: \(iosVersion)")
            return true
        } catch {
            print("Failed to initialize writers: \(error.localizedDescription)")
            return false
        }
    }

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

    func writePoseRow(timestamp: Int64, pose: [Float], trackingState: String) {
        if !isInitialized || writersPaused { return }
        let startNs = currentTimeNs()
        guard pose.count >= 7 else { return }
        let line =
            "\(timestamp),\(pose[0]),\(pose[1]),\(pose[2]),\(pose[3]),\(pose[4]),\(pose[5]),\(pose[6]),\(trackingState)\n"
        writeToHandle(posesHandle, line)
        poseCount += 1
        totalBytesWritten += Int64(line.utf8.count)
        recordWriterLatency(startNs: startNs)
    }

    func writeImuSamples(samples: [ImuSample]) {
        if !isInitialized || writersPaused || samples.isEmpty { return }
        let startNs = currentTimeNs()
        var sb = ""
        for sample in samples {
            sb +=
                "\(sample.timestampNs),\(sample.accelX),\(sample.accelY),\(sample.accelZ),\(sample.gyroX),\(sample.gyroY),\(sample.gyroZ)\n"
            imuSampleCount += 1
        }
        writeToHandle(imuHandle, sb)
        totalBytesWritten += Int64(sb.utf8.count)
        recordWriterLatency(startNs: startNs)
    }

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
        let line =
            "\(frameIndex),\(globalArFrameIndex),\(arkitTimestampNs),\(trackingState),\(encoded ? 1 : 0),\(depthAvailable ? 1 : 0),\(pointCloudAvailable ? 1 : 0),\(meshAvailable ? 1 : 0)\n"
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
        logSystem(
            message:
                "Tracking state transition: \(previousState) -> \(nextState) at \(timestampNs) ns")
    }

    func writeTrackingState(
        timestampNs: Int64, state: UInt8, reason: UInt8, stateStr: String, reasonStr: String
    ) {
        // Legacy CSV writer does not write tracking state as a separate topic
    }

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
        // Legacy CSV writer does not write device metrics
    }

    func writeCompressedRgbFrame(timestamp: Int64, jpegData: Data) {
        // Legacy writer does not support compressed RGB; no-op.
    }

    func writePointCloud(timestamp: Int64, frameData: PointCloudFrameData?) {
        guard isInitialized, let frameData = frameData else { return }
        let startNs = currentTimeNs()
        writePointCloudFormatIfNeeded()
        zipArchive?.addStoredEntry(
            path: "pointcloud/frame_\(timestamp).bin",
            data: frameData.bytes.prefix(frameData.validSize))
        pointCloudCount += 1
        totalBytesWritten += Int64(frameData.validSize)
        if frameData.pointCount <= 0 {
            logSystem(message: "WARN: point cloud frame \(timestamp) has no points")
        }
        recordWriterLatency(startNs: startNs)
    }

    func writeDepthFrame(timestamp: Int64, frameData: DepthFrameData?) -> Bool {
        guard isInitialized, let frameData = frameData else { return false }
        let startNs = currentTimeNs()
        let expectedSize = frameData.width * frameData.height * frameData.bytesPerPixel
        if frameData.validSize != expectedSize {
            skippedDepthFrames += 1
            logSystem(
                message:
                    "WARN: skipping depth frame \(timestamp), invalid size \(frameData.validSize), expected \(expectedSize)"
            )
            return false
        }

        writeDepthFormatIfNeeded(
            width: frameData.width,
            height: frameData.height,
            bytesPerPixel: frameData.bytesPerPixel,
            pixelStride: frameData.pixelStride,
            rowStride: frameData.rowStride,
            unit: frameData.unit
        )
        zipArchive?.addStoredEntry(
            path: "depth/frame_\(timestamp).bin", data: frameData.bytes.prefix(frameData.validSize))
        depthFrameCountWriter += 1
        totalBytesWritten += Int64(frameData.validSize)
        recordWriterLatency(startNs: startNs)
        return true
    }

    func writeMeshFrame(timestamp: Int64, frameData: MeshFrameData?) -> Bool {
        guard isInitialized, let frameData = frameData else { return false }
        let startNs = currentTimeNs()
        writeMeshFormatIfNeeded()
        zipArchive?.addStoredEntry(
            path: "mesh/frame_\(timestamp).bin", data: frameData.bytes.prefix(frameData.validSize))
        meshFrameCountWriter += 1
        totalBytesWritten += Int64(frameData.validSize)
        recordWriterLatency(startNs: startNs)
        return true
    }

    func writeDepthIntrinsics(timestampNs: Int64, intrinsics: [String: Any]) {
        // No-op for JSON-only writer
    }

    func writeIntrinsics(timestampNs: Int64, intrinsics: [String: Any]) {
        if !isInitialized { return }
        guard let dataDir = spatialDataDir else { return }
        let json = """
            {
              "focalLengthX": \(intrinsics["focalLengthX"] ?? 0),
              "focalLengthY": \(intrinsics["focalLengthY"] ?? 0),
              "principalPointX": \(intrinsics["principalPointX"] ?? 0),
              "principalPointY": \(intrinsics["principalPointY"] ?? 0),
              "imageWidth": \(intrinsics["imageWidth"] ?? 0),
              "imageHeight": \(intrinsics["imageHeight"] ?? 0),
              "distortionCoeffs": []
            }
            """
        let file = dataDir.appendingPathComponent("intrinsics.json")
        try? json.write(to: file, atomically: true, encoding: .utf8)
        totalBytesWritten += Int64(json.utf8.count)
    }

    @discardableResult
    func writeMetadata(metadata: [String: Any?]) -> Bool {
        if !isInitialized { return false }
        guard let dataDir = spatialDataDir else { return false }
        let file = dataDir.appendingPathComponent("metadata.json")

        // Strategy 1: Custom pretty-print serializer (original path)
        do {
            let json = toJsonValue(metadata, level: 0)
            try json.write(to: file, atomically: true, encoding: .utf8)
            totalBytesWritten += Int64(json.utf8.count)
            logSystem(message: "metadata.json written")
            return true
        } catch {
            logError(
                message: "metadata.json write failed (toJsonValue): \(error.localizedDescription)",
                error: error)
        }

        // Strategy 2: JSONSerialization (lower peak memory — streams to Data without pretty-print intermediates)
        do {
            let sanitized = sanitizeForJsonSerialization(metadata)
            let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
            try data.write(to: file, options: .atomic)
            totalBytesWritten += Int64(data.count)
            logSystem(message: "metadata.json written (JSONSerialization fallback)")
            return true
        } catch {
            logError(
                message:
                    "metadata.json write failed (JSONSerialization): \(error.localizedDescription)",
                error: error)
        }

        // Strategy 3: Minimal essential-only metadata (tiny allocation, should always succeed)
        do {
            let minimal = extractMinimalMetadata(from: metadata)
            let data = try JSONSerialization.data(withJSONObject: minimal, options: [])
            try data.write(to: file, options: .atomic)
            totalBytesWritten += Int64(data.count)
            logSystem(message: "metadata.json written (minimal fallback)")
            return true
        } catch {
            logError(
                message:
                    "metadata.json write failed (minimal fallback): \(error.localizedDescription)",
                error: error)
        }

        return false
    }

    /// Strips nil/Optional values so JSONSerialization doesn't choke on them.
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

    /// Extracts only the fields the Dart upload flow actually needs.
    private func extractMinimalMetadata(from metadata: [String: Any?]) -> [String: Any] {
        var minimal: [String: Any] = [
            "metadata_fallback": true
        ]
        let essentialKeys: [String] = [
            "session_duration_seconds", "durationSeconds",
            "total_video_frames_encoded", "framesRecorded",
            "total_imu_samples", "imuSamples",
            "device_model", "ios_version",
            "resolution", "fps",
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

    func addVideoBytesWritten(videoBytes: Int64) {
        if videoBytes > 0 {
            totalBytesWritten += videoBytes
        }
    }

    func getVideoOutputPath() -> String? {
        guard let dir = sessionDir else { return nil }
        let name = dir.lastPathComponent.replacingOccurrences(of: "session_", with: "")
        return dir.appendingPathComponent("video_\(name).mp4").path
    }

    func getSessionDirectory() -> String? {
        return sessionDir?.path
    }

    func getRecordingStats() -> [String: Any] {
        return [
            "poseCount": poseCount,
            "imuSampleCount": imuSampleCount,
            "pointCloudCount": pointCloudCount,
            "depthFrameCount": depthFrameCountWriter,
            "meshFrameCount": meshFrameCountWriter,
            "skippedDepthFrames": skippedDepthFrames,
            "totalBytesWritten": totalBytesWritten,
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
        posesHandle?.synchronizeFile()
        imuHandle?.synchronizeFile()
        frameLogHandle?.synchronizeFile()
        systemLogHandle?.synchronizeFile()
    }

    func setCameraImuExtrinsic(rotationRowMajor: [Double], translationXYZ: (x: Double, y: Double, z: Double)) {
        // Legacy CSV writer doesn't emit /tf — no-op. MCAP writer handles this.
    }

    func captureFreeStorageAfterSnapshot() {
        if let session = sessionDir,
            let values = try? session.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        {
            freeStorageAfterBytes = capacity
        }
    }

    func createSpatialDataZip() -> (Bool, String?, String?) {
        guard let dataDir = spatialDataDir else { return (false, nil, "spatialDataDir is nil") }
        guard let session = sessionDir else { return (false, nil, "sessionDir is nil") }
        guard let zipURL = zipFileURL else { return (false, nil, "zipFileURL is nil") }

        // Flush and close text writers
        closeHandle(&posesHandle)
        closeHandle(&imuHandle)
        closeHandle(&frameLogHandle)
        closeHandle(&systemLogHandle)

        guard let archive = zipArchive else { return (false, nil, "zipArchive is nil") }

        do {
            // Add remaining text files from spatial_data/ directory
            let enumerator = FileManager.default.enumerator(
                at: dataDir, includingPropertiesForKeys: [.isRegularFileKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true {
                    let relativePath = fileURL.path.replacingOccurrences(
                        of: dataDir.path + "/", with: "")
                    let data = try Data(contentsOf: fileURL)
                    archive.addStoredEntry(path: relativePath, data: data)
                }
            }

            archive.finalize()
            zipArchive = nil

            guard FileManager.default.fileExists(atPath: zipURL.path) else {
                return (false, nil, "session_data zip is missing after finalization")
            }

            // Copy metadata.json to session root
            let metadataFile = dataDir.appendingPathComponent("metadata.json")
            if FileManager.default.fileExists(atPath: metadataFile.path) {
                let dest = session.appendingPathComponent("metadata.json")
                try? FileManager.default.copyItem(at: metadataFile, to: dest)
            }

            try FileManager.default.removeItem(at: dataDir)
            print("session_data zip created: \(zipURL.path)")
            return (true, zipURL.path, nil)
        } catch {
            print("Failed to finalize session_data zip: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }

    func finalizeWriters() {
        closeHandle(&posesHandle)
        closeHandle(&imuHandle)
        closeHandle(&frameLogHandle)
        closeHandle(&systemLogHandle)
        zipArchive?.finalize()
        zipArchive = nil
        captureFreeStorageAfterSnapshot()
        isInitialized = false
        print("Dataset writers finalized")
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
        depthFormatWritten = false
        pointcloudFormatWritten = false
        meshFormatWritten = false
        writerLatencyTotalNs = 0
        writerLatencySamples = 0
        writersPaused = false
        zipArchive = nil
        zipFileURL = nil
        print("Dataset writer released")
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

    private func writeDepthFormatIfNeeded(
        width: Int,
        height: Int,
        bytesPerPixel: Int,
        pixelStride: Int,
        rowStride: Int,
        unit: String
    ) {
        if depthFormatWritten { return }
        let json = """
            {
              "width": \(width),
              "height": \(height),
              "bytes_per_pixel": \(bytesPerPixel),
              "format": "uint16",
              "unit": "\(unit)",
              "endianness": "little",
              "source_pixel_stride": \(pixelStride),
              "source_row_stride": \(rowStride),
              "includes_padding": false
            }
            """
        zipArchive?.addStoredEntry(path: "depth_format.json", data: Data(json.utf8))
        totalBytesWritten += Int64(json.utf8.count)
        depthFormatWritten = true
        logSystem(message: "depth_format.json written")
    }

    private func writePointCloudFormatIfNeeded() {
        if pointcloudFormatWritten { return }
        let json = """
            {
              "header": {
                "timestamp_ns": "int64",
                "point_count": "int32"
              },
              "floats_per_point": 4,
              "float_type": "float32",
              "point_layout": ["x", "y", "z", "confidence"],
              "endianness": "little"
            }
            """
        zipArchive?.addStoredEntry(path: "pointcloud_format.json", data: Data(json.utf8))
        totalBytesWritten += Int64(json.utf8.count)
        pointcloudFormatWritten = true
    }

    private func writeMeshFormatIfNeeded() {
        if meshFormatWritten { return }
        let json = """
            {
              "header": {
                "timestamp_ns": "int64",
                "anchor_count": "uint32"
              },
              "per_anchor": {
                "anchor_id": "uuid_16_bytes",
                "transform": "float32_4x4_column_major",
                "vertex_count": "uint32",
                "vertices": "float32_xyz",
                "face_count": "uint32",
                "face_indices": "uint32_triangles"
              },
              "endianness": "little"
            }
            """
        zipArchive?.addStoredEntry(path: "mesh_format.json", data: Data(json.utf8))
        totalBytesWritten += Int64(json.utf8.count)
        meshFormatWritten = true
        logSystem(message: "mesh_format.json written")
    }

    // MARK: - JSON Serialization

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
        return
            raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Simple Zip Archive Writer (STORED entries only, no compression)

/// Minimal zip writer that supports STORED entries for binary data written incrementally.
class ZipArchiveWriter {
    private var fileHandle: FileHandle?
    private var centralDirectory: Data = Data()
    private var entryCount: UInt16 = 0
    private var currentOffset: UInt32 = 0

    init(url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
    }

    func addStoredEntry(path: String, data: Data) {
        guard let fh = fileHandle else { return }
        let pathData = Data(path.utf8)
        let crc = crc32Checksum(data)
        let size = UInt32(data.count)
        let localHeaderOffset = currentOffset

        // Local file header
        var localHeader = Data()
        localHeader.appendUInt32(0x0403_4b50)  // signature
        localHeader.appendUInt16(20)  // version needed
        localHeader.appendUInt16(0)  // flags
        localHeader.appendUInt16(0)  // compression (STORED)
        localHeader.appendUInt16(0)  // mod time
        localHeader.appendUInt16(0)  // mod date
        localHeader.appendUInt32(crc)  // CRC-32
        localHeader.appendUInt32(size)  // compressed size
        localHeader.appendUInt32(size)  // uncompressed size
        localHeader.appendUInt16(UInt16(pathData.count))  // filename length
        localHeader.appendUInt16(0)  // extra field length

        fh.write(localHeader)
        fh.write(pathData)
        fh.write(data)
        currentOffset += UInt32(localHeader.count + pathData.count + data.count)

        // Central directory entry
        var cdEntry = Data()
        cdEntry.appendUInt32(0x0201_4b50)  // signature
        cdEntry.appendUInt16(20)  // version made by
        cdEntry.appendUInt16(20)  // version needed
        cdEntry.appendUInt16(0)  // flags
        cdEntry.appendUInt16(0)  // compression
        cdEntry.appendUInt16(0)  // mod time
        cdEntry.appendUInt16(0)  // mod date
        cdEntry.appendUInt32(crc)
        cdEntry.appendUInt32(size)
        cdEntry.appendUInt32(size)
        cdEntry.appendUInt16(UInt16(pathData.count))
        cdEntry.appendUInt16(0)  // extra field length
        cdEntry.appendUInt16(0)  // comment length
        cdEntry.appendUInt16(0)  // disk number
        cdEntry.appendUInt16(0)  // internal attrs
        cdEntry.appendUInt32(0)  // external attrs
        cdEntry.appendUInt32(localHeaderOffset)
        cdEntry.append(pathData)

        centralDirectory.append(cdEntry)
        entryCount += 1
    }

    /// Adds a STORED entry by streaming from a file on disk.
    /// Single-pass: uses data descriptor (bit 3) so CRC and sizes go after the data.
    /// CRC is computed via zlib.crc32() which uses hardware ARM CRC32 instructions.
    func addStoredEntryFromFile(path: String, fileURL: URL) throws {
        guard let fh = fileHandle else { return }
        let pathData = Data(path.utf8)
        let chunkSize = 1024 * 1024  // 1 MB

        // Get file size
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let size32 = UInt32(truncatingIfNeeded: fileSize)

        let startTime = CFAbsoluteTimeGetCurrent()
        print(
            "ZipArchiveWriter: addStoredEntryFromFile - single-pass starting for '\(path)' (\(fileSize) bytes)"
        )

        let localHeaderOffset = currentOffset

        // Write local file header with bit 3 set (data descriptor follows data)
        // CRC and sizes are 0 in the header; real values go in the data descriptor
        var localHeader = Data()
        localHeader.appendUInt32(0x0403_4b50)  // signature
        localHeader.appendUInt16(20)  // version needed
        localHeader.appendUInt16(0x0008)  // flags: bit 3 = data descriptor
        localHeader.appendUInt16(0)  // compression (STORED)
        localHeader.appendUInt16(0)  // mod time
        localHeader.appendUInt16(0)  // mod date
        localHeader.appendUInt32(0)  // CRC-32 (deferred)
        localHeader.appendUInt32(0)  // compressed size (deferred)
        localHeader.appendUInt32(0)  // uncompressed size (deferred)
        localHeader.appendUInt16(UInt16(pathData.count))  // filename length
        localHeader.appendUInt16(0)  // extra field length

        fh.write(localHeader)
        fh.write(pathData)
        currentOffset += UInt32(localHeader.count + pathData.count)

        // Single pass: read file in chunks, compute CRC and stream to output simultaneously
        let readHandle = try FileHandle(forReadingFrom: fileURL)
        var runningCrc: uLong = 0
        while autoreleasepool(invoking: {
            let chunk = readHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { return false }
            chunk.withUnsafeBytes { rawBuffer in
                let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: Bytef.self)
                runningCrc = zlib.crc32(runningCrc, ptr, uInt(rawBuffer.count))
            }
            fh.write(chunk)
            currentOffset += UInt32(chunk.count)
            return true
        }) {}
        readHandle.closeFile()
        let crc = UInt32(runningCrc)

        // Write data descriptor: signature + CRC + compressed size + uncompressed size
        var dataDescriptor = Data()
        dataDescriptor.appendUInt32(0x0807_4b50)  // data descriptor signature
        dataDescriptor.appendUInt32(crc)
        dataDescriptor.appendUInt32(size32)  // compressed size (STORED = uncompressed)
        dataDescriptor.appendUInt32(size32)  // uncompressed size
        fh.write(dataDescriptor)
        currentOffset += UInt32(dataDescriptor.count)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print(
            "ZipArchiveWriter: addStoredEntryFromFile - single-pass done in \(String(format: "%.2f", elapsed))s"
        )

        // Central directory entry (gets the real CRC and sizes)
        var cdEntry = Data()
        cdEntry.appendUInt32(0x0201_4b50)  // signature
        cdEntry.appendUInt16(20)  // version made by
        cdEntry.appendUInt16(20)  // version needed
        cdEntry.appendUInt16(0x0008)  // flags: bit 3 = data descriptor
        cdEntry.appendUInt16(0)  // compression
        cdEntry.appendUInt16(0)  // mod time
        cdEntry.appendUInt16(0)  // mod date
        cdEntry.appendUInt32(crc)
        cdEntry.appendUInt32(size32)
        cdEntry.appendUInt32(size32)
        cdEntry.appendUInt16(UInt16(pathData.count))
        cdEntry.appendUInt16(0)  // extra field length
        cdEntry.appendUInt16(0)  // comment length
        cdEntry.appendUInt16(0)  // disk number
        cdEntry.appendUInt16(0)  // internal attrs
        cdEntry.appendUInt32(0)  // external attrs
        cdEntry.appendUInt32(localHeaderOffset)
        cdEntry.append(pathData)

        centralDirectory.append(cdEntry)
        entryCount += 1
    }

    func finalize() {
        guard let fh = fileHandle else { return }
        let cdOffset = currentOffset
        fh.write(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // End of central directory
        var eocd = Data()
        eocd.appendUInt32(0x0605_4b50)  // signature
        eocd.appendUInt16(0)  // disk number
        eocd.appendUInt16(0)  // disk with CD
        eocd.appendUInt16(entryCount)
        eocd.appendUInt16(entryCount)
        eocd.appendUInt32(cdSize)
        eocd.appendUInt32(cdOffset)
        eocd.appendUInt16(0)  // comment length

        fh.write(eocd)
        fh.synchronizeFile()
        fh.closeFile()
        fileHandle = nil
    }

    private func crc32Checksum(_ data: Data) -> UInt32 {
        return data.withUnsafeBytes { rawBuffer -> UInt32 in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                return 0
            }
            return UInt32(zlib.crc32(0, ptr, uInt(rawBuffer.count)))
        }
    }
}

extension Data {
    fileprivate mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
    fileprivate mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
