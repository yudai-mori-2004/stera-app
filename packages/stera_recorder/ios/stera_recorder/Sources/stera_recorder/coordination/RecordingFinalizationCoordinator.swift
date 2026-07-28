import Foundation

class RecordingFinalizationCoordinator {

    private static let maxPlausibleDurationMs: Int64 = 12 * 60 * 60 * 1000
    private static let mcapDurationSlackMs: Int64 = 60_000

    struct CoreStats {
        let durationMs: Int64
        let durationSeconds: Double
        let arkitFps: Double
        let encodedVideoFps: Double
        let depthFps: Double
        let pointcloudFps: Double
        let meshFps: Double
        let imuFps: Double
        let bitrate: Int64
    }

    func computeCoreStats(
        nowMs: Int64,
        recordingStartTimeMs: Int64,
        totalPausedDurationMs: Int64,
        arkitFrameCount: Int,
        encodedVideoFrameCount: Int,
        depthFrameCount: Int,
        pointCloudFrameCount: Int,
        meshFrameCount: Int,
        imuSampleCount: Int,
        videoFileSizeBytes: Int64?,
        mcapDurationMs: Int64? = nil
    ) -> CoreStats {
        // Compute wall-clock-based duration. This is the authoritative upper
        // bound — the MCAP-message-based duration must not exceed it (plus a
        // small slack for end-of-session writes). A bad MCAP message with an
        // out-of-band timestamp (e.g. epoch-ns leaking in where uptime-ns is
        // expected) would otherwise produce a duration of ~55 years.
        let wallClockMs: Int64?
        if recordingStartTimeMs > 0 {
            let computedWallClockMs = nowMs - recordingStartTimeMs - totalPausedDurationMs
            if computedWallClockMs >= 0 && computedWallClockMs <= Self.maxPlausibleDurationMs {
                wallClockMs = computedWallClockMs
            } else {
                wallClockMs = nil
                print("RecordingFinalizationCoordinator: rejecting implausible wallClockMs=\(computedWallClockMs) (nowMs=\(nowMs), recordingStartTimeMs=\(recordingStartTimeMs)). Likely mixed epoch-ms and uptime-ms clocks.")
            }
        } else {
            // recordingStartTime never got set — we can't compute wall-clock.
            // Prefer MCAP below if available; otherwise return 0.
            wallClockMs = nil
        }
        let saneMcapDurationMs: Int64? = {
            guard let mcapMs = mcapDurationMs,
                  mcapMs > 0,
                  mcapMs <= Self.maxPlausibleDurationMs else {
                return nil
            }
            return mcapMs
        }()
        let durationMs: Int64
        if let wallClockMs = wallClockMs {
            let mcapMsValidUpperBoundMs = wallClockMs + Self.mcapDurationSlackMs
            if let mcapMs = saneMcapDurationMs, mcapMs <= mcapMsValidUpperBoundMs {
                durationMs = mcapMs
            } else {
                durationMs = wallClockMs
                if let mcapMs = mcapDurationMs, mcapMs > mcapMsValidUpperBoundMs {
                    print("RecordingFinalizationCoordinator: rejecting implausible mcapDurationMs=\(mcapMs) (wallClock=\(wallClockMs)); falling back to wall-clock. Likely a corrupt MCAP message timestamp.")
                }
            }
        } else if let mcapMs = saneMcapDurationMs {
            durationMs = mcapMs
        } else {
            durationMs = 0
            if let mcapMs = mcapDurationMs, mcapMs > Self.maxPlausibleDurationMs {
                print("RecordingFinalizationCoordinator: rejecting implausible mcapDurationMs=\(mcapMs); no sane wall-clock duration available.")
            }
        }
        let durationSeconds = Double(durationMs) / 1000.0
        let arkitFps = durationSeconds > 0.0 ? Double(arkitFrameCount) / durationSeconds : 0.0
        let encodedVideoFps = durationSeconds > 0.0 ? Double(encodedVideoFrameCount) / durationSeconds : 0.0
        let depthFps = durationSeconds > 0.0 ? Double(depthFrameCount) / durationSeconds : 0.0
        let pointcloudFps = durationSeconds > 0.0 ? Double(pointCloudFrameCount) / durationSeconds : 0.0
        let meshFps = durationSeconds > 0.0 ? Double(meshFrameCount) / durationSeconds : 0.0
        let imuFps = durationSeconds > 0.0 ? Double(imuSampleCount) / durationSeconds : 0.0
        let fileSizeBytes = videoFileSizeBytes ?? 0
        let bitrate: Int64
        if durationSeconds > 0.0 && fileSizeBytes > 0 {
            bitrate = Int64((Double(fileSizeBytes) * 8.0) / durationSeconds)
        } else {
            bitrate = 0
        }
        return CoreStats(
            durationMs: durationMs,
            durationSeconds: durationSeconds,
            arkitFps: arkitFps,
            encodedVideoFps: encodedVideoFps,
            depthFps: depthFps,
            pointcloudFps: pointcloudFps,
            meshFps: meshFps,
            imuFps: imuFps,
            bitrate: bitrate
        )
    }

    func buildSessionSummary(
        durationSeconds: Double,
        arkitFps: Double,
        encodedVideoFps: Double,
        depthFps: Double,
        meshFps: Double,
        imuFps: Double,
        cameraResolution: String,
        recordingResolution: String,
        isLowQualityMode: Bool,
        lowQualityReason: String?,
        maxEncoderQueueDepth: Int,
        encoderBackpressureDetected: Bool
    ) -> String {
        var summary = ""
        summary += "Duration (s): \(String(format: "%.3f", durationSeconds))\n"
        summary += "ARKit FPS: \(String(format: "%.3f", arkitFps))\n"
        summary += "RGB Sampling FPS: \(String(format: "%.3f", encodedVideoFps))\n"
        summary += "Depth Frequency (Hz): \(String(format: "%.3f", depthFps))\n"
        summary += "Mesh Frequency (Hz): \(String(format: "%.3f", meshFps))\n"
        summary += "IMU Frequency (Hz): \(String(format: "%.3f", imuFps))\n"
        summary += "Camera Resolution: \(cameraResolution)\n"
        summary += "Recording Resolution: \(recordingResolution)\n"
        summary += "Low Quality Mode: \(isLowQualityMode ? "yes (\(lowQualityReason ?? "unknown"))" : "no")\n"
        summary += "Encoder Queue Depth (max): \(maxEncoderQueueDepth)\n"
        summary += "Encoder Backpressure Detected: \(encoderBackpressureDetected ? "yes" : "no")\n"
        return summary
    }
}
