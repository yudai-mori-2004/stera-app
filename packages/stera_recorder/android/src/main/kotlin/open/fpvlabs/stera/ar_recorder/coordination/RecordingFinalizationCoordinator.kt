package open.fpvlabs.stera.ar_recorder.coordination

class RecordingFinalizationCoordinator {
    data class CoreStats(
        val durationMs: Long,
        val durationSeconds: Double,
        val arcoreFps: Double,
        val encodedVideoFps: Double,
        val depthFps: Double,
        val pointcloudFps: Double,
        val imuFps: Double,
        val bitrate: Long
    )

    fun computeCoreStats(
        nowMs: Long,
        recordingStartTimeMs: Long,
        totalPausedDurationMs: Long,
        arcoreFrameCount: Int,
        encodedVideoFrameCount: Int,
        depthFrameCount: Int,
        pointCloudFrameCount: Int,
        imuSampleCount: Int,
        videoFileSizeBytes: Long?
    ): CoreStats {
        val durationMs = (nowMs - recordingStartTimeMs - totalPausedDurationMs).coerceAtLeast(0L)
        val durationSeconds = durationMs / 1000.0
        val arcoreFps = if (durationSeconds > 0.0) arcoreFrameCount.toDouble() / durationSeconds else 0.0
        val encodedVideoFps = if (durationSeconds > 0.0) encodedVideoFrameCount.toDouble() / durationSeconds else 0.0
        val depthFps = if (durationSeconds > 0.0) depthFrameCount.toDouble() / durationSeconds else 0.0
        val pointcloudFps = if (durationSeconds > 0.0) pointCloudFrameCount.toDouble() / durationSeconds else 0.0
        val imuFps = if (durationSeconds > 0.0) imuSampleCount.toDouble() / durationSeconds else 0.0
        val bitrate = if (durationSeconds > 0.0 && (videoFileSizeBytes ?: 0L) > 0L) {
            (((videoFileSizeBytes ?: 0L) * 8.0) / durationSeconds).toLong()
        } else {
            0L
        }
        return CoreStats(
            durationMs = durationMs,
            durationSeconds = durationSeconds,
            arcoreFps = arcoreFps,
            encodedVideoFps = encodedVideoFps,
            depthFps = depthFps,
            pointcloudFps = pointcloudFps,
            imuFps = imuFps,
            bitrate = bitrate
        )
    }

    fun buildSessionSummary(
        durationSeconds: Double,
        arcoreFps: Double,
        encodedVideoFps: Double,
        depthFps: Double,
        imuFps: Double,
        cameraResolution: String,
        recordingResolution: String,
        isLowQualityMode: Boolean,
        lowQualityReason: String?,
        maxEncoderQueueDepth: Int,
        encoderBackpressureDetected: Boolean
    ): String {
        return buildString {
            append("Duration (s): ")
            append("%.3f".format(durationSeconds))
            append("\nARCore FPS: ")
            append("%.3f".format(arcoreFps))
            append("\nRGB Sampling FPS: ")
            append("%.3f".format(encodedVideoFps))
            append("\nDepth Frequency (Hz): ")
            append("%.3f".format(depthFps))
            append("\nIMU Frequency (Hz): ")
            append("%.3f".format(imuFps))
            append("\nCamera Resolution: ")
            append(cameraResolution)
            append("\nRecording Resolution: ")
            append(recordingResolution)
            append("\nLow Quality Mode: ")
            append(if (isLowQualityMode) "yes (${lowQualityReason ?: "unknown"})" else "no")
            append("\nEncoder Queue Depth (max): ")
            append(maxEncoderQueueDepth)
            append("\nEncoder Backpressure Detected: ")
            append(if (encoderBackpressureDetected) "yes" else "no")
            append("\n")
        }
    }
}
