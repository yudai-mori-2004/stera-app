import Foundation
import UIKit

/// Assembles the metadata.json map and related finalization artefacts.
/// Reads from RecordingMetricsState and RuntimeHealthManager, produces immutable output.
class MetadataAssembler {
    private static let dropLogInlineLimit = 1000
    private static let encoderQueueSoftLimit = 2
    private static let depthAssociationWideThresholdNs: Int64 = 40_000_000

    private static func videoProfileLabel(forConfiguredWidth w: Int, configuredHeight h: Int) -> String {
        let shortSide = min(w, h)
        return shortSide >= 1000 ? "1080p" : "720p"
    }

    private let metricsCollector: RecordingMetricsCollector

    init(metricsCollector: RecordingMetricsCollector) {
        self.metricsCollector = metricsCollector
    }

    struct FinalizationInput {
        let metrics: RecordingMetricsState
        let health: RuntimeHealthManager
        let coreStats: RecordingFinalizationCoordinator.CoreStats
        let sessionManager: ArSessionManager
        let frameProcessor: ArFrameProcessor
        let imuCollector: ImuCollector
        let datasetWriter: DatasetWriter
        let cameraImuEstimator: CameraImuExtrinsicEstimator
        let recordingResolution: String
        let cameraResolution: String
        let previewWidth: Int
        let previewHeight: Int
        let isLowQualityMode: Bool
        let lowQualityReason: String?
        let upscaleApplied: Bool
        let arkitVersion: String
        let appVersion: String
        let appBuild: String
        let imuSampleCount: Int
        let totalBytesWritten: Int64
        let estimatedDatasetSizeBytes: Int64
        let sizeWarningThresholdBytes: Int64
        let recordingStartTime: Int64
    }

    struct FinalizationResult {
        let metadata: [String: Any?]
        let associatedDepthFrames: Int
        let unmatchedRgbFrames: Int
        let missingDepthCount: Int
        let maxAssociationDeltaNs: Int64
    }

    func assemble(input: FinalizationInput) -> FinalizationResult {
        let m = input.metrics
        let h = input.health
        let cs = input.coreStats
        let fp = input.frameProcessor
        let dw = input.datasetWriter

        let durationSeconds = cs.durationSeconds
        let durationMs = cs.durationMs
        let encodedVideoFps = cs.encodedVideoFps
        let arkitFps = cs.arkitFps
        let depthFps = cs.depthFps
        let pointcloudFps = cs.pointcloudFps
        let imuFps = durationSeconds > 0.0 ? Double(input.imuSampleCount) / durationSeconds : 0.0

        // Association stats
        m.effectiveDepthAssociationThresholdNs = Self.depthAssociationWideThresholdNs
        let associationStats = metricsCollector.computeDepthAssociations(
            rgbTimestamps: m.depthAssociationCandidateRgbTimestamps,
            depthTimestamps: m.depthFrameTimestamps,
            thresholdNs: m.effectiveDepthAssociationThresholdNs
        )
        let associatedDepthFrames = associationStats.associated
        let unmatchedRgbFrames = associationStats.unmatched
        let missingDepthCount = unmatchedRgbFrames
        let maxAssociationDeltaNs = associationStats.maxDeltaNs

        // Stream overlap
        let streamOverlap = metricsCollector.computeStreamOverlap(ranges: [
            TimestampWindow(minNs: m.rgbTimestampRange.minNs, maxNs: m.rgbTimestampRange.maxNs, count: m.rgbTimestampRange.count),
            TimestampWindow(minNs: m.imuTimestampRange.minNs, maxNs: m.imuTimestampRange.maxNs, count: m.imuTimestampRange.count),
            TimestampWindow(minNs: m.depthTimestampRange.minNs, maxNs: m.depthTimestampRange.maxNs, count: m.depthTimestampRange.count),
            TimestampWindow(minNs: m.pointCloudTimestampRange.minNs, maxNs: m.pointCloudTimestampRange.maxNs, count: m.pointCloudTimestampRange.count),
            TimestampWindow(minNs: m.poseTimestampRange.minNs, maxNs: m.poseTimestampRange.maxNs, count: m.poseTimestampRange.count),
            TimestampWindow(minNs: m.meshTimestampRange.minNs, maxNs: m.meshTimestampRange.maxNs, count: m.meshTimestampRange.count)
        ])

        // Computed rates
        let averageRenderLoopMs = m.renderLoopIterations > 0
            ? (Double(m.renderLoopTotalNs) / Double(m.renderLoopIterations)) / 1_000_000.0
            : 0.0

        let averageDepthAcquisitionMs = m.depthAcquisitionSamples > 0
            ? (Double(m.depthAcquisitionTotalLatencyNs) / Double(m.depthAcquisitionSamples)) / 1_000_000.0
            : 0.0

        let associationCandidateCount = m.depthAssociationCandidateRgbTimestamps.count
        let rgbSamplingRatio = m.globalArFrameIndex > 0
            ? Double(m.rgbEncodedFrameIndices.count) / Double(m.globalArFrameIndex)
            : 0.0
        let encoderFailureRate = m.globalArFrameIndex > 0
            ? Double(m.rgbEncoderFailureCount) / Double(m.globalArFrameIndex)
            : 0.0

        let arkitNativeFps: Double = {
            let est = estimatedArkitFps(m)
            return est > 0.0 ? est : arkitFps
        }()

        let encoderFrameIntervalAvgMs = m.encoderIntervalMeanNs / 1_000_000.0
        let encoderFrameIntervalStdMs: Double = m.encoderIntervalSamples > 1
            ? sqrt(m.encoderIntervalM2Ns / (Double(m.encoderIntervalSamples) - 1.0)) / 1_000_000.0
            : 0.0

        let writerAvgLatencyMs = dw.getWriterAverageLatencyMs()
        let cumulativeFrameDrift = max(m.totalExpectedFrameCount - Int64(m.encodedVideoFrameCount), 0)

        let rgbDepthSyncRate = m.rgbEncodedFrameIndices.isEmpty ? 0.0
            : Double(m.depthFrameIndices.count) / Double(m.rgbEncodedFrameIndices.count)

        let driftPerMinute = durationSeconds > 0.0
            ? Double(cumulativeFrameDrift) / (durationSeconds / 60.0) : 0.0
        let driftWarning = driftPerMinute > 10.0
        let memoryStable = !h.memoryGrowthDetected && !h.leakSuspected
        let queueStable = m.maxEncoderQueueDepth <= Self.encoderQueueSoftLimit

        let productionCertifiedModeB =
            durationSeconds >= 120.0 &&
            encodedVideoFps >= 29.5 &&
            encoderFrameIntervalStdMs <= 5.0 &&
            cumulativeFrameDrift <= 50 &&
            !m.encoderBackpressureDetected &&
            m.maxEncoderQueueDepth <= Self.encoderQueueSoftLimit &&
            !h.memoryGrowthDetected &&
            rgbDepthSyncRate > 0.995

        // Drop log externalization
        let externalizeDropLog =
            m.rgbEncoderFailureFrameIndices.count > Self.dropLogInlineLimit ||
            m.depthDroppedFrameIndices.count > Self.dropLogInlineLimit ||
            m.pointcloudDroppedFrameIndices.count > Self.dropLogInlineLimit ||
            m.poseDroppedFrameIndices.count > Self.dropLogInlineLimit ||
            m.meshDroppedFrameIndices.count > Self.dropLogInlineLimit

        let frameDropLogPath: String? = externalizeDropLog ? dw.writeFrameDropLog(dropLog: [
            "rgb_encoder_failure_frame_indices": m.rgbEncoderFailureFrameIndices,
            "depth_dropped_frame_indices": m.depthDroppedFrameIndices,
            "pointcloud_dropped_frame_indices": m.pointcloudDroppedFrameIndices,
            "pose_dropped_frame_indices": m.poseDroppedFrameIndices,
            "mesh_dropped_frame_indices": m.meshDroppedFrameIndices
        ]) : nil

        let rgbFailureIndicesForMetadata: [Int] = externalizeDropLog ? [] : m.rgbEncoderFailureFrameIndices
        let depthDroppedIndicesForMetadata: [Int] = externalizeDropLog ? [] : m.depthDroppedFrameIndices
        let pointcloudDroppedIndicesForMetadata: [Int] = externalizeDropLog ? [] : m.pointcloudDroppedFrameIndices
        let poseDroppedIndicesForMetadata: [Int] = externalizeDropLog ? [] : m.poseDroppedFrameIndices

        let encoderQueueDepth = m.encoderQueueDepth()
        let resolutionFallback = m.actualVideoWidth != 0 && m.actualVideoHeight != 0 &&
            (m.actualVideoWidth != m.configuredVideoWidth || m.actualVideoHeight != m.configuredVideoHeight)

        let associationSuccessRate = associationCandidateCount > 0
            ? Double(associatedDepthFrames) / Double(associationCandidateCount)
            : 0.0

        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion

        var metadata: [String: Any?] = [
            "device_model": deviceModel,
            "ios_version": systemVersion,
            "app_version": input.appVersion,
            "app_build": input.appBuild,
            "arkit_version": input.arkitVersion,
            "resolution": input.recordingResolution,
            "camera_resolution": input.cameraResolution,
            "recording_resolution": input.recordingResolution,
            "preview_resolution": "\(input.previewWidth)x\(input.previewHeight)",
            "video_profile": "\(Self.videoProfileLabel(forConfiguredWidth: m.configuredVideoWidth, configuredHeight: m.configuredVideoHeight))_\(m.targetEncodeFps)fps_landscape",
            "target_orientation": "landscape",
            "fps": encodedVideoFps,
            "bitrate": cs.bitrate,
            "encoder_mode": "fixed_\(m.targetEncodeFps)fps_sampling",
            "sampling_strategy": "timestamp_gate",
            "rgb_sampling_strategy": "timestamp_gate",
            "sampling_strategy_detail": "deterministic_frame_schedule",
            "rgb_intentional_downsample": true,
            "rgb_target_fps": m.targetEncodeFps,
            "arkit_native_fps": arkitNativeFps,
            "total_rgb_frames": m.arkitFrameCount,
            "total_depth_frames": m.depthFrameCount,
            "total_pointcloud_frames": m.pointCloudFrameCount,
            "total_mesh_frames": m.meshFrameCount,
            "total_imu_samples": input.imuSampleCount,
            "tracking_loss_events": m.trackingLossEvents,
            "errors_encountered": m.totalErrorsEncountered,
            "depth_supported": input.sessionManager.isDepthSupported,
            "mesh_supported": input.sessionManager.isMeshSupported,
            "session_duration_seconds": durationSeconds,
            "total_ar_frames": m.globalArFrameIndex,
            "total_ar_frames_received": m.arkitFrameCount,
            "total_video_frames_encoded": m.encodedVideoFrameCount,
            "session_start_timestamp_ns": m.sessionStartTimestampNs,
            "deterministic_frame_index": m.deterministicFrameIndex,
            "total_expected_frame_slots": m.totalExpectedFrameCount,
            "cumulative_frame_drift": cumulativeFrameDrift,
            "drift_resync_event_count": m.driftResyncEventCount,
            "rgb_encoded_count": m.rgbEncodedFrameIndices.count,
            "rgb_sampling_skipped_count": m.rgbSamplingSkippedCount,
            "rgb_encoder_failure_count": m.rgbEncoderFailureCount,
            "rgb_sampling_ratio": rgbSamplingRatio,
            "encoder_failure_rate": encoderFailureRate,
            "depth_captured_count": m.depthFrameIndices.count,
            "depth_dropped_count": m.depthDroppedFrameIndices.count,
            "pointcloud_captured_count": m.pointcloudFrameIndices.count,
            "pointcloud_dropped_count": m.pointcloudDroppedFrameIndices.count,
            "mesh_captured_count": m.meshFrameIndices.count,
            "mesh_dropped_count": m.meshDroppedFrameIndices.count,
            "pose_dropped_count": m.poseDroppedFrameIndices.count,
            "rgb_encoder_failure_frame_indices": rgbFailureIndicesForMetadata,
            "depth_dropped_frame_indices": depthDroppedIndicesForMetadata,
            "pointcloud_dropped_frame_indices": pointcloudDroppedIndicesForMetadata,
            "pose_dropped_frame_indices": poseDroppedIndicesForMetadata,
            "frame_drop_log_externalized": externalizeDropLog,
            "frame_drop_log_path": frameDropLogPath,
            "skipped_depth_frames": m.skippedDepthFrameCount,
            "skippedDepthFrames": m.skippedDepthFrameCount,
            "totalArFramesReceived": m.arkitFrameCount,
            "totalVideoFramesEncoded": m.encodedVideoFrameCount,
            "totalDepthFramesCaptured": m.depthFrameCount,
            "totalPointCloudFramesCaptured": m.pointCloudFrameCount,
            "rgb_start_ns": m.rgbTimestampRange.startOrZero(),
            "rgb_end_ns": m.rgbTimestampRange.endOrZero(),
            "imu_start_ns": m.imuTimestampRange.startOrZero(),
            "imu_end_ns": m.imuTimestampRange.endOrZero(),
            "depth_start_ns": m.depthTimestampRange.startOrZero(),
            "depth_end_ns": m.depthTimestampRange.endOrZero(),
            "pointcloud_start_ns": m.pointCloudTimestampRange.startOrZero(),
            "pointcloud_end_ns": m.pointCloudTimestampRange.endOrZero(),
            "pose_start_ns": m.poseTimestampRange.startOrZero(),
            "pose_end_ns": m.poseTimestampRange.endOrZero(),
            "mesh_start_ns": m.meshTimestampRange.startOrZero(),
            "mesh_end_ns": m.meshTimestampRange.endOrZero(),
            "stream_durations_ms": [
                "rgb": Double(m.rgbTimestampRange.durationNsOrZero()) / 1_000_000.0,
                "imu": Double(m.imuTimestampRange.durationNsOrZero()) / 1_000_000.0,
                "depth": Double(m.depthTimestampRange.durationNsOrZero()) / 1_000_000.0,
                "pointcloud": Double(m.pointCloudTimestampRange.durationNsOrZero()) / 1_000_000.0,
                "pose": Double(m.poseTimestampRange.durationNsOrZero()) / 1_000_000.0,
                "mesh": Double(m.meshTimestampRange.durationNsOrZero()) / 1_000_000.0
            ],
            "stream_overlap_valid": streamOverlap,
            "rgb_frames": m.rgbFrameTimestamps.count,
            "depth_frames": m.depthFrameTimestamps.count,
            "association_candidate_rgb_frames": associationCandidateCount,
            "associated_depth_frames": associatedDepthFrames,
            "unmatched_rgb_frames": unmatchedRgbFrames,
            "missing_depth_count": missingDepthCount,
            "depth_association_threshold_ns_effective": m.effectiveDepthAssociationThresholdNs,
            "association_jitter_window_ms": Double(m.effectiveDepthAssociationThresholdNs) / 1_000_000.0,
            "max_timestamp_delta_ms": Double(maxAssociationDeltaNs) / 1_000_000.0,
            "performance_metrics": [
                "avg_render_loop_ms": averageRenderLoopMs,
                "encoder_queue_depth": encoderQueueDepth,
                "max_encoder_queue_depth": m.maxEncoderQueueDepth,
                "encoder_frame_interval_avg_ms": encoderFrameIntervalAvgMs,
                "encoder_frame_interval_std_ms": encoderFrameIntervalStdMs,
                "writer_avg_latency_ms": writerAvgLatencyMs,
                "avg_depth_acquisition_latency_ms": averageDepthAcquisitionMs,
                "max_depth_acquisition_latency_ms": Double(m.depthAcquisitionMaxLatencyNs) / 1_000_000.0,
                "avg_imu_callback_latency_ms": input.imuCollector.getAverageCallbackLatencyNs() / 1_000_000.0,
                "max_imu_callback_latency_ms": Double(input.imuCollector.getMaxCallbackLatencyNs()) / 1_000_000.0
            ] as [String: Any],
            "storage": [
                "path": dw.getSessionDirectory() as Any,
                "free_before_bytes": dw.getFreeStorageBeforeBytes(),
                "free_after_bytes": dw.getFreeStorageAfterBytes(),
                "total_bytes_written": input.totalBytesWritten
            ] as [String: Any],
            "compression": [
                "depth_compression": "none",
                "pointcloud_compression": "none",
                "compression_hooks_ready": true
            ] as [String: Any],
            "estimated_dataset_size_bytes": input.estimatedDatasetSizeBytes,
            "size_warning_threshold_bytes": input.sizeWarningThresholdBytes,
            "configured_width": m.configuredVideoWidth,
            "configured_height": m.configuredVideoHeight,
            "actual_width": m.actualVideoWidth,
            "actual_height": m.actualVideoHeight,
            "fps_target": m.targetEncodeFps,
            "encoder_target_bitrate": m.targetVideoBitrate,
            "fps_target_runtime": m.targetEncodeFps,
            "resolution_fallback": resolutionFallback,
            "video_orientation_valid": m.actualVideoWidth >= m.actualVideoHeight,
            "arkit_fps": arkitFps,
            "encoded_video_fps": encodedVideoFps,
            "depth_fps": depthFps,
            "pointcloud_fps": pointcloudFps,
            "pointcloud_mode": "sparse_keyframe_based",
            "pointcloud_expected_fps": "variable",
            "imu_fps": imuFps,
            "imu_intrinsics": Self.imuIntrinsicsDict(ImuIntrinsics.default),
            "imu_reference_frame": input.imuCollector.activeReferenceFrameName(),
            "arkit_fps_actual": input.sessionManager.activeArkitFps,
            "is_low_quality_mode": input.isLowQualityMode,
            "low_quality_reason": input.lowQualityReason,
            "upscale_applied": input.upscaleApplied,
            "segment_rotation_enabled": false,
            "segments_count": 1,
            "encoder_dynamic_mode": m.dynamicEncoderMode,
            "production_ready_mode_b": true,
            "bitrate_active": m.activeVideoBitrate,
            "bitrate_reduction_count": m.bitrateReducedCount,
            "bitrate_restore_count": m.bitrateRestoreCount,
            "depth_buffer_allocations_after_start": fp.getDepthBufferAllocations(),
            "pointcloud_buffer_allocations_after_start": fp.getPointCloudBufferAllocations(),
            "mesh_buffer_allocations_after_start": fp.getMeshBufferAllocations(),
            "pointcloud_soft_skip_count": m.pointCloudSoftSkipCount,
            "tracking_pause_depth_skip_count": m.trackingPauseDepthSkipCount,
            "tracking_pause_count": m.trackingPauseCount,
            "tracking_pause_total_offset_ms": Double(m.trackingPauseTotalOffsetNs) / 1_000_000.0,
            "depth_attempt_count": m.depthAttemptCount,
            "depth_success_count": m.depthSuccessCount,
            "depth_cadence_reset_count": m.depthCadenceResetCount,
            "pointcloud_acquire_count": fp.getPointCloudAcquireCount(),
            "pointcloud_release_count": fp.getPointCloudReleaseCount(),
            "depth_image_acquire_count": fp.getDepthImageAcquireCount(),
            "depth_image_close_count": fp.getDepthImageCloseCount(),
            "depth_acquire_count": fp.getDepthImageAcquireCount(),
            "depth_close_count": fp.getDepthImageCloseCount(),
            "pointcloud_release_mismatch": fp.getPointCloudAcquireCount() != fp.getPointCloudReleaseCount(),
            "depth_image_close_mismatch": fp.getDepthImageAcquireCount() != fp.getDepthImageCloseCount(),
            "maintenance_cycle_count": h.maintenanceCycleCount,
            "encoder_backpressure_detected": m.encoderBackpressureDetected,
            "thermal_throttling_detected": h.thermalThrottlingDetected,
            "thermal_status_last": h.thermalStatusLabel,
            "thermal_state_transition_count": h.thermalStateTransitionCount,
            "fps_drift_detected": h.fpsDriftDetected,
            "memory_growth_detected": h.memoryGrowthDetected,
            "max_memory_usage_mb": h.maxMemoryUsageMb,
            "leak_suspected": h.leakSuspected,
            "production_certified_mode_b": productionCertifiedModeB,
            "arcoreFrameCount": m.arkitFrameCount,
            "encodedVideoFrameCount": m.encodedVideoFrameCount,
            "submittedToEncoderFrameCount": m.submittedToEncoderFrameCount,
            "depthFrameCount": m.depthFrameCount,
            "pointCloudFrameCount": m.pointCloudFrameCount,
            "poseFrameCount": m.poseFrameCount,
            "meshFrameCount": m.meshFrameCount
        ]

        metadata["dataset_quality_summary"] = [
            "rgb_fps_effective": encodedVideoFps,
            "depth_fps_effective": depthFps,
            "rgb_depth_sync_rate": rgbDepthSyncRate,
            "encoder_failure_rate": encoderFailureRate,
            "max_timestamp_delta_ms": Double(maxAssociationDeltaNs) / 1_000_000.0,
            "memory_stable": memoryStable,
            "queue_stable": queueStable,
            "cumulative_frame_drift": cumulativeFrameDrift,
            "drift_per_minute": driftPerMinute,
            "drift_warning": driftWarning,
            "drift_resync_event_count": m.driftResyncEventCount,
            "production_certified_mode_b": productionCertifiedModeB
        ] as [String: Any]

        metadata["encoder_queue_depth_after_fix"] = encoderQueueDepth
        metadata["max_encoder_queue_depth_after_fix"] = m.maxEncoderQueueDepth
        metadata["encoder_frame_interval_avg_ms"] = encoderFrameIntervalAvgMs
        metadata["encoder_frame_interval_std_ms"] = encoderFrameIntervalStdMs

        metadata["camera_imu_extrinsic"] = Self.cameraImuExtrinsicDict(estimator: input.cameraImuEstimator)

        return FinalizationResult(
            metadata: metadata,
            associatedDepthFrames: associatedDepthFrames,
            unmatchedRgbFrames: unmatchedRgbFrames,
            missingDepthCount: missingDepthCount,
            maxAssociationDeltaNs: maxAssociationDeltaNs
        )
    }

    private func estimatedArkitFps(_ m: RecordingMetricsState) -> Double {
        if m.arkitCadenceSamples <= 0 || m.arkitCadenceMeanIntervalNs <= 0.0 { return 0.0 }
        return 1_000_000_000.0 / m.arkitCadenceMeanIntervalNs
    }

    /// Camera↔IMU extrinsic block. Prefers this session's freshly solved estimate;
    /// falls back to the cached value (loaded at session start) when motion was
    /// insufficient. Returns `nil` if the device has no estimate at all yet — first
    /// session on a new device with too little motion.
    private static func cameraImuExtrinsicDict(estimator: CameraImuExtrinsicEstimator) -> [String: Any]? {
        let result = estimator.finalizedResult() ?? estimator.cachedValue()
        guard let r = result else { return nil }
        // Repack the 9-element row-major rotation into a 3x3 nested array for readability.
        let rotation3x3: [[Double]] = [
            [r.rotationRowMajor[0], r.rotationRowMajor[1], r.rotationRowMajor[2]],
            [r.rotationRowMajor[3], r.rotationRowMajor[4], r.rotationRowMajor[5]],
            [r.rotationRowMajor[6], r.rotationRowMajor[7], r.rotationRowMajor[8]]
        ]
        return [
            "rotation_matrix_3x3": rotation3x3,
            "translation_xyz_m": [r.translationXYZ.x, r.translationXYZ.y, r.translationXYZ.z],
            "translation_source": r.translationSource.rawValue,
            "estimation_method": r.estimationMethod,
            "calibration_window_s": r.calibrationWindowS,
            "rotation_residual_median_rad_s": r.rotationResidualMedianRadS,
            "translation_residual_median_m_s2": r.translationResidualMedianMS2,
            "rotation_samples": r.rotationSamples,
            "drift_vs_cache_deg": r.driftVsCacheDeg,
            "from_cache": r.fromCache
        ]
    }

    private static func imuIntrinsicsDict(_ i: ImuIntrinsics) -> [String: Any] {
        return [
            "accel_noise_density": i.accelNoiseDensity,
            "gyro_noise_density": i.gyroNoiseDensity,
            "accel_bias_random_walk": i.accelBiasRandomWalk,
            "gyro_bias_random_walk": i.gyroBiasRandomWalk,
            "accel_bias": [i.accelBias.x, i.accelBias.y, i.accelBias.z],
            "gyro_bias": [i.gyroBias.x, i.gyroBias.y, i.gyroBias.z],
            "source": i.source
        ]
    }
}
