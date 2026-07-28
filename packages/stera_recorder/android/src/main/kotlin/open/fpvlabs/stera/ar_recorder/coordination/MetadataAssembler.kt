package open.fpvlabs.stera.ar_recorder.coordination

import android.os.Build
import open.fpvlabs.stera.ar_recorder.data.DatasetWriter
import open.fpvlabs.stera.ar_recorder.encoding.EglManager
import open.fpvlabs.stera.ar_recorder.metrics.RecordingMetricsCollector
import open.fpvlabs.stera.ar_recorder.metrics.TimestampWindow
import open.fpvlabs.stera.ar_recorder.sensors.ImuCollector
import open.fpvlabs.stera.ar_recorder.session.ArFrameProcessor
import open.fpvlabs.stera.ar_recorder.session.ArSessionManager
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Assembles the metadata.json map and related finalization artefacts
 * (drop-log externalization, production-certification check, association stats).
 *
 * This class is essentially stateless; it reads from [RecordingMetricsState] and
 * [RuntimeHealthManager] and produces immutable output.
 */
class MetadataAssembler(
    private val metricsCollector: RecordingMetricsCollector
) {
    companion object {
        private const val VIDEO_FPS_FIXED = 30
        private const val DROP_LOG_INLINE_LIMIT = 1000
        private const val ENCODER_QUEUE_SOFT_LIMIT = 2
        private const val DEPTH_ASSOCIATION_WIDE_THRESHOLD_NS = 40_000_000L
    }

    private fun videoProfileLabel(configuredWidth: Int, configuredHeight: Int): String {
        val shortSide = minOf(configuredWidth, configuredHeight)
        return if (shortSide >= 1000) "1080p" else "720p"
    }

    data class FinalizationInput(
        val metrics: RecordingMetricsState,
        val health: RuntimeHealthManager,
        val coreStats: RecordingFinalizationCoordinator.CoreStats,
        val sessionManager: ArSessionManager,
        val frameProcessor: ArFrameProcessor,
        val imuCollector: ImuCollector,
        val datasetWriter: DatasetWriter,
        val eglManager: EglManager,
        val recordingResolution: String,
        val cameraResolution: String,
        val previewWidth: Int,
        val previewHeight: Int,
        val isLowQualityMode: Boolean,
        val lowQualityReason: String?,
        val upscaleApplied: Boolean,
        val arcoreVersion: String,
        val appVersion: String,
        val appBuild: String,
        val imuSampleCount: Int,
        val totalBytesWritten: Long,
        val estimatedDatasetSizeBytes: Long,
        val sizeWarningThresholdBytes: Long,
        val recordingStartTime: Long
    )

    data class FinalizationResult(
        val metadata: LinkedHashMap<String, Any?>,
        val associatedDepthFrames: Int,
        val unmatchedRgbFrames: Int,
        val missingDepthCount: Int,
        val maxAssociationDeltaNs: Long
    )

    /**
     * Assembles the complete metadata map for the recording session.
     */
    fun assemble(input: FinalizationInput): FinalizationResult {
        val m = input.metrics
        val h = input.health
        val cs = input.coreStats
        val fp = input.frameProcessor
        val dw = input.datasetWriter

        val durationSeconds = cs.durationSeconds
        val durationMs = cs.durationMs
        val encodedVideoFps = cs.encodedVideoFps
        val arcoreFps = cs.arcoreFps
        val depthFps = cs.depthFps
        val pointcloudFps = cs.pointcloudFps
        val bitrate = cs.bitrate
        val imuFps = if (durationSeconds > 0.0) input.imuSampleCount.toDouble() / durationSeconds else 0.0

        // Association stats
        m.effectiveDepthAssociationThresholdNs = DEPTH_ASSOCIATION_WIDE_THRESHOLD_NS
        val associationStats = metricsCollector.computeDepthAssociations(
            rgbTimestamps = m.depthAssociationCandidateRgbTimestamps.toList(),
            depthTimestamps = m.depthFrameTimestamps.toList(),
            thresholdNs = m.effectiveDepthAssociationThresholdNs
        )
        val associatedDepthFrames = associationStats.associated
        val unmatchedRgbFrames = associationStats.unmatched
        val missingDepthCount = unmatchedRgbFrames
        val maxAssociationDeltaNs = associationStats.maxDeltaNs

        // Stream overlap
        val streamOverlap = metricsCollector.computeStreamOverlap(
            listOf(
                TimestampWindow(m.rgbTimestampRange.minNs, m.rgbTimestampRange.maxNs, m.rgbTimestampRange.count),
                TimestampWindow(m.imuTimestampRange.minNs, m.imuTimestampRange.maxNs, m.imuTimestampRange.count),
                TimestampWindow(m.depthTimestampRange.minNs, m.depthTimestampRange.maxNs, m.depthTimestampRange.count),
                TimestampWindow(m.pointCloudTimestampRange.minNs, m.pointCloudTimestampRange.maxNs, m.pointCloudTimestampRange.count),
                TimestampWindow(m.poseTimestampRange.minNs, m.poseTimestampRange.maxNs, m.poseTimestampRange.count)
            )
        )

        // Computed rates
        val averageRenderLoopMs = if (m.renderLoopIterations > 0) {
            (m.renderLoopTotalNs.toDouble() / m.renderLoopIterations.toDouble()) / 1_000_000.0
        } else 0.0

        val averageDepthAcquisitionMs = if (m.depthAcquisitionSamples > 0) {
            (m.depthAcquisitionTotalLatencyNs.toDouble() / m.depthAcquisitionSamples.toDouble()) / 1_000_000.0
        } else 0.0

        val associationCandidateCount = m.depthAssociationCandidateRgbTimestamps.size
        val rgbSamplingRatio = if (m.globalArFrameIndex > 0) {
            m.rgbEncodedFrameIndices.size.toDouble() / m.globalArFrameIndex.toDouble()
        } else 0.0

        val encoderFailureRate = if (m.globalArFrameIndex > 0) {
            m.rgbEncoderFailureCount.toDouble() / m.globalArFrameIndex.toDouble()
        } else 0.0

        val arcoreNativeFps = estimatedArcoreFps(m).takeIf { it > 0.0 } ?: arcoreFps

        val encoderFrameIntervalAvgMs = m.encoderIntervalMeanNs / 1_000_000.0
        val encoderFrameIntervalStdMs = if (m.encoderIntervalSamples > 1) {
            sqrt(m.encoderIntervalM2Ns / (m.encoderIntervalSamples.toDouble() - 1.0)) / 1_000_000.0
        } else 0.0

        val writerAvgLatencyMs = dw.getWriterAverageLatencyMs()
        val depthPoolStarvationEvents = fp.getDepthPoolStarvationEvents()
        val pointcloudPoolStarvationEvents = fp.getPointCloudPoolStarvationEvents()
        val totalPoolStarvationEvents = depthPoolStarvationEvents + pointcloudPoolStarvationEvents
        val depthPoolCapacity = fp.getDepthPoolCapacity().coerceAtLeast(1)
        val pointCloudPoolCapacity = fp.getPointCloudPoolCapacity().coerceAtLeast(1)
        val depthPoolHighWatermarkRatio = fp.getDepthPoolMaxInUse().toDouble() / depthPoolCapacity.toDouble()
        val pointCloudPoolHighWatermarkRatio = fp.getPointCloudPoolMaxInUse().toDouble() / pointCloudPoolCapacity.toDouble()
        val poolHighWatermarkRatio = max(depthPoolHighWatermarkRatio, pointCloudPoolHighWatermarkRatio)
        val cumulativeFrameDrift = (m.totalExpectedFrameCount - m.encodedVideoFrameCount.get().toLong()).coerceAtLeast(0L)

        val rgbDepthSyncRate = if (m.rgbEncodedFrameIndices.isNotEmpty()) {
            m.depthFrameIndices.size.toDouble() / m.rgbEncodedFrameIndices.size.toDouble()
        } else 0.0

        val driftPerMinute = if (durationSeconds > 0.0) {
            cumulativeFrameDrift.toDouble() / (durationSeconds / 60.0)
        } else 0.0
        val driftWarning = driftPerMinute > 10.0
        val memoryStable = !h.memoryGrowthDetected && !h.leakSuspected
        val queueStable = m.maxEncoderQueueDepth <= ENCODER_QUEUE_SOFT_LIMIT
        val poolStable =
            fp.getDepthPoolMisses() == 0 &&
                fp.getPointCloudPoolMisses() == 0 &&
                totalPoolStarvationEvents == 0

        val productionCertifiedModeB =
            durationSeconds >= 120.0 &&
                encodedVideoFps >= 29.5 &&
                encoderFrameIntervalStdMs <= 5.0 &&
                poolHighWatermarkRatio <= 0.8 &&
                cumulativeFrameDrift <= 50 &&
                !m.encoderBackpressureDetected &&
                h.memoryStableLongWindow &&
                totalPoolStarvationEvents == 0 &&
                m.maxEncoderQueueDepth <= ENCODER_QUEUE_SOFT_LIMIT &&
                !h.memoryGrowthDetected &&
                rgbDepthSyncRate > 0.995

        // Drop log externalization
        val externalizeDropLog =
            m.rgbEncoderFailureFrameIndices.size > DROP_LOG_INLINE_LIMIT ||
                m.depthDroppedFrameIndices.size > DROP_LOG_INLINE_LIMIT ||
                m.pointcloudDroppedFrameIndices.size > DROP_LOG_INLINE_LIMIT ||
                m.poseDroppedFrameIndices.size > DROP_LOG_INLINE_LIMIT
        val frameDropLogPath = if (externalizeDropLog) {
            dw.writeFrameDropLog(
                mapOf(
                    "rgb_encoder_failure_frame_indices" to m.rgbEncoderFailureFrameIndices,
                    "depth_dropped_frame_indices" to m.depthDroppedFrameIndices,
                    "pointcloud_dropped_frame_indices" to m.pointcloudDroppedFrameIndices,
                    "pose_dropped_frame_indices" to m.poseDroppedFrameIndices
                )
            )
        } else null

        val rgbFailureIndicesForMetadata: List<Int> = if (externalizeDropLog) emptyList() else m.rgbEncoderFailureFrameIndices
        val depthDroppedIndicesForMetadata: List<Int> = if (externalizeDropLog) emptyList() else m.depthDroppedFrameIndices
        val pointcloudDroppedIndicesForMetadata: List<Int> = if (externalizeDropLog) emptyList() else m.pointcloudDroppedFrameIndices
        val poseDroppedIndicesForMetadata: List<Int> = if (externalizeDropLog) emptyList() else m.poseDroppedFrameIndices

        val encoderQueueDepth = m.encoderQueueDepth()
        val resolutionFallback = m.actualVideoWidth != 0 && m.actualVideoHeight != 0 &&
            (m.actualVideoWidth != m.configuredVideoWidth || m.actualVideoHeight != m.configuredVideoHeight)

        val associationSuccessRate = if (associationCandidateCount > 0) {
            associatedDepthFrames.toDouble() / associationCandidateCount.toDouble()
        } else 0.0

        val metadata = linkedMapOf<String, Any?>(
            "device_model" to Build.MODEL,
            "android_version" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "app_version" to input.appVersion,
            "app_build" to input.appBuild,
            "arcore_version" to input.arcoreVersion,
            "resolution" to input.recordingResolution,
            "camera_resolution" to input.cameraResolution,
            "recording_resolution" to input.recordingResolution,
            "preview_resolution" to "${input.previewWidth}x${input.previewHeight}",
            "video_profile" to "${videoProfileLabel(m.configuredVideoWidth, m.configuredVideoHeight)}_${m.targetEncodeFps}fps_landscape",
            "target_orientation" to "landscape",
            "fps" to encodedVideoFps,
            "bitrate" to bitrate,
            "encoder_mode" to "fixed_30fps_sampling",
            "sampling_strategy" to "timestamp_gate",
            "rgb_sampling_strategy" to "timestamp_gate",
            "sampling_strategy_detail" to "deterministic_frame_schedule",
            "rgb_intentional_downsample" to true,
            "rgb_target_fps" to VIDEO_FPS_FIXED,
            "arcore_native_fps" to arcoreNativeFps,
            "total_rgb_frames" to m.arcoreFrameCount.get(),
            "total_depth_frames" to m.depthFrameCount.get(),
            "total_pointcloud_frames" to m.pointCloudFrameCount.get(),
            "total_imu_samples" to input.imuSampleCount,
            "tracking_loss_events" to m.trackingLossEvents,
            "errors_encountered" to m.totalErrorsEncountered,
            "depth_supported" to input.sessionManager.isDepthSupported,
            "session_duration_seconds" to durationSeconds,
            "total_ar_frames" to m.globalArFrameIndex,
            "total_ar_frames_received" to m.arcoreFrameCount.get(),
            "total_video_frames_encoded" to m.encodedVideoFrameCount.get(),
            "session_start_timestamp_ns" to m.sessionStartTimestampNs,
            "deterministic_frame_index" to m.deterministicFrameIndex,
            "total_expected_frame_slots" to m.totalExpectedFrameCount,
            "cumulative_frame_drift" to cumulativeFrameDrift,
            "drift_resync_event_count" to m.driftResyncEventCount,
            "rgb_encoded_count" to m.rgbEncodedFrameIndices.size,
            "rgb_sampling_skipped_count" to m.rgbSamplingSkippedCount,
            "rgb_encoder_failure_count" to m.rgbEncoderFailureCount,
            "rgb_sampling_ratio" to rgbSamplingRatio,
            "encoder_failure_rate" to encoderFailureRate,
            "depth_captured_count" to m.depthFrameIndices.size,
            "depth_dropped_count" to m.depthDroppedFrameIndices.size,
            "pointcloud_captured_count" to m.pointcloudFrameIndices.size,
            "pointcloud_dropped_count" to m.pointcloudDroppedFrameIndices.size,
            "pose_dropped_count" to m.poseDroppedFrameIndices.size,
            "rgb_encoder_failure_frame_indices" to rgbFailureIndicesForMetadata,
            "depth_dropped_frame_indices" to depthDroppedIndicesForMetadata,
            "pointcloud_dropped_frame_indices" to pointcloudDroppedIndicesForMetadata,
            "pose_dropped_frame_indices" to poseDroppedIndicesForMetadata,
            "frame_drop_log_externalized" to externalizeDropLog,
            "frame_drop_log_path" to frameDropLogPath,
            "skipped_depth_frames" to m.skippedDepthFrameCount.get(),
            "skippedDepthFrames" to m.skippedDepthFrameCount.get(),
            "totalArFramesReceived" to m.arcoreFrameCount.get(),
            "totalVideoFramesEncoded" to m.encodedVideoFrameCount.get(),
            "totalDepthFramesCaptured" to m.depthFrameCount.get(),
            "totalPointCloudFramesCaptured" to m.pointCloudFrameCount.get(),
            "rgb_start_ns" to m.rgbTimestampRange.startOrZero(),
            "rgb_end_ns" to m.rgbTimestampRange.endOrZero(),
            "imu_start_ns" to m.imuTimestampRange.startOrZero(),
            "imu_end_ns" to m.imuTimestampRange.endOrZero(),
            "depth_start_ns" to m.depthTimestampRange.startOrZero(),
            "depth_end_ns" to m.depthTimestampRange.endOrZero(),
            "pointcloud_start_ns" to m.pointCloudTimestampRange.startOrZero(),
            "pointcloud_end_ns" to m.pointCloudTimestampRange.endOrZero(),
            "pose_start_ns" to m.poseTimestampRange.startOrZero(),
            "pose_end_ns" to m.poseTimestampRange.endOrZero(),
            "stream_durations_ms" to mapOf(
                "rgb" to m.rgbTimestampRange.durationNsOrZero() / 1_000_000.0,
                "imu" to m.imuTimestampRange.durationNsOrZero() / 1_000_000.0,
                "depth" to m.depthTimestampRange.durationNsOrZero() / 1_000_000.0,
                "pointcloud" to m.pointCloudTimestampRange.durationNsOrZero() / 1_000_000.0,
                "pose" to m.poseTimestampRange.durationNsOrZero() / 1_000_000.0
            ),
            "stream_overlap_valid" to streamOverlap,
            "rgb_frames" to m.rgbFrameTimestamps.size,
            "depth_frames" to m.depthFrameTimestamps.size,
            "association_candidate_rgb_frames" to associationCandidateCount,
            "associated_depth_frames" to associatedDepthFrames,
            "unmatched_rgb_frames" to unmatchedRgbFrames,
            "missing_depth_count" to missingDepthCount,
            "depth_association_threshold_ns_effective" to m.effectiveDepthAssociationThresholdNs,
            "association_jitter_window_ms" to (m.effectiveDepthAssociationThresholdNs / 1_000_000.0),
            "max_timestamp_delta_ms" to (maxAssociationDeltaNs.toDouble() / 1_000_000.0),
            "performance_metrics" to mapOf(
                "avg_render_loop_ms" to averageRenderLoopMs,
                "encoder_queue_depth" to encoderQueueDepth,
                "encoder_queue_depth_after_fix" to encoderQueueDepth,
                "max_encoder_queue_depth" to m.maxEncoderQueueDepth,
                "max_encoder_queue_depth_after_fix" to m.maxEncoderQueueDepth,
                "encoder_frame_interval_avg_ms" to encoderFrameIntervalAvgMs,
                "encoder_frame_interval_std_ms" to encoderFrameIntervalStdMs,
                "writer_avg_latency_ms" to writerAvgLatencyMs,
                "avg_depth_acquisition_latency_ms" to averageDepthAcquisitionMs,
                "max_depth_acquisition_latency_ms" to m.depthAcquisitionMaxLatencyNs / 1_000_000.0,
                "avg_imu_callback_latency_ms" to input.imuCollector.getAverageCallbackLatencyNs() / 1_000_000.0,
                "max_imu_callback_latency_ms" to input.imuCollector.getMaxCallbackLatencyNs() / 1_000_000.0
            ),
            "storage" to mapOf(
                "path" to dw.getSessionDirectory(),
                "free_before_bytes" to dw.getFreeStorageBeforeBytes(),
                "free_after_bytes" to dw.getFreeStorageAfterBytes(),
                "total_bytes_written" to input.totalBytesWritten
            ),
            "compression" to mapOf(
                "depth_compression" to "none",
                "pointcloud_compression" to "none",
                "compression_hooks_ready" to true
            ),
            "estimated_dataset_size_bytes" to input.estimatedDatasetSizeBytes,
            "size_warning_threshold_bytes" to input.sizeWarningThresholdBytes,
            "configured_width" to m.configuredVideoWidth,
            "configured_height" to m.configuredVideoHeight,
            "actual_width" to m.actualVideoWidth,
            "actual_height" to m.actualVideoHeight,
            "fps_target" to m.targetEncodeFps,
            "encoder_target_bitrate" to m.targetVideoBitrate,
            "fps_target_runtime" to m.targetEncodeFps,
            "resolution_fallback" to resolutionFallback,
            "video_orientation_valid" to (m.actualVideoWidth >= m.actualVideoHeight),
            "arcore_fps" to arcoreFps,
            "encoded_video_fps" to encodedVideoFps,
            "depth_fps" to depthFps,
            "pointcloud_fps" to pointcloudFps,
            "pointcloud_mode" to "sparse_keyframe_based",
            "pointcloud_expected_fps" to "variable",
            "imu_fps" to imuFps,
            "is_low_quality_mode" to input.isLowQualityMode,
            "low_quality_reason" to input.lowQualityReason,
            "upscale_applied" to input.upscaleApplied,
            "segment_rotation_enabled" to false,
            "segments_count" to 1,
            "encoder_dynamic_mode" to m.dynamicEncoderMode,
            "production_ready_mode_b" to true,
            "bitrate_active" to m.activeVideoBitrate,
            "bitrate_reduction_count" to m.bitrateReducedCount,
            "bitrate_restore_count" to m.bitrateRestoreCount,
            "depth_buffer_allocations_after_start" to fp.getDepthBufferAllocations(),
            "pointcloud_buffer_allocations_after_start" to fp.getPointCloudBufferAllocations(),
            "depth_pool_miss_count" to fp.getDepthPoolMisses(),
            "pointcloud_pool_miss_count" to fp.getPointCloudPoolMisses(),
            "depth_pool_capacity" to fp.getDepthPoolCapacity(),
            "pointcloud_pool_capacity" to fp.getPointCloudPoolCapacity(),
            "depth_pool_min_available" to fp.getDepthPoolMinAvailable(),
            "pointcloud_pool_min_available" to fp.getPointCloudPoolMinAvailable(),
            "depth_pool_max_in_use" to fp.getDepthPoolMaxInUse(),
            "pointcloud_pool_max_in_use" to fp.getPointCloudPoolMaxInUse(),
            "depth_pool_high_watermark_ratio" to depthPoolHighWatermarkRatio,
            "pointcloud_pool_high_watermark_ratio" to pointCloudPoolHighWatermarkRatio,
            "pool_high_watermark_ratio" to poolHighWatermarkRatio,
            "pointcloud_soft_skip_count" to m.pointCloudSoftSkipCount,
            "tracking_pause_depth_skip_count" to m.trackingPauseDepthSkipCount,
            "tracking_pause_count" to m.trackingPauseCount,
            "tracking_pause_total_offset_ms" to (m.trackingPauseTotalOffsetNs / 1_000_000.0),
            "depth_attempt_count" to m.depthAttemptCount,
            "depth_success_count" to m.depthSuccessCount,
            "depth_cadence_reset_count" to m.depthCadenceResetCount,
            "pointcloud_acquire_count" to fp.getPointCloudAcquireCount(),
            "pointcloud_release_count" to fp.getPointCloudReleaseCount(),
            "depth_image_acquire_count" to fp.getDepthImageAcquireCount(),
            "depth_image_close_count" to fp.getDepthImageCloseCount(),
            "depth_acquire_count" to fp.getDepthImageAcquireCount(),
            "depth_close_count" to fp.getDepthImageCloseCount(),
            "pointcloud_release_mismatch" to (fp.getPointCloudAcquireCount() != fp.getPointCloudReleaseCount()),
            "depth_image_close_mismatch" to (fp.getDepthImageAcquireCount() != fp.getDepthImageCloseCount()),
            "maintenance_cycle_count" to h.maintenanceCycleCount,
            "maintenance_forced_drain_count" to h.maintenanceForcedDrainCount,
            "maintenance_last_encoder_queue_depth" to h.maintenanceLastEncoderQueueDepth,
            "encoder_backpressure_detected" to m.encoderBackpressureDetected,
            "egl_preview_surface_active" to input.eglManager.hasPreviewSurface(),
            "egl_encoder_surface_active" to input.eglManager.hasEncoderSurface(),
            "thermal_throttling_detected" to h.thermalThrottlingDetected,
            "thermal_status_last" to h.thermalStatusLabel,
            "thermal_state_transition_count" to h.thermalStateTransitionCount,
            "thermal_bitrate_clamp_active" to h.thermalBitrateClampActive,
            "thermal_clamp_applied_count" to h.thermalClampAppliedCount,
            "thermal_clamp_released_count" to h.thermalClampReleasedCount,
            "fps_drift_detected" to h.fpsDriftDetected,
            "memory_growth_detected" to h.memoryGrowthDetected,
            "memory_growth_window_seconds" to (120_000L / 1000),
            "memory_growth_consecutive_maintenance_cycles" to h.memoryGrowthConsecutiveMaintenanceCycles,
            "memory_stable_maintenance_cycles" to h.memoryStableMaintenanceCycles,
            "memory_stable_long_window" to h.memoryStableLongWindow,
            "gc_drop_observed" to h.gcDropObservedInWindow,
            "memory_baseline_resets" to h.memoryBaselineResetCount,
            "max_memory_usage_mb" to h.maxMemoryUsageMb,
            "memory_high_watermark_mb" to h.memoryHighWatermarkMb,
            "max_native_heap_mb" to h.maxNativeHeapMb,
            "max_direct_buffer_mb_estimate" to h.maxDirectBufferMbEstimate,
            "leak_suspected" to h.leakSuspected,
            "depth_pool_starvation_events" to depthPoolStarvationEvents,
            "pointcloud_pool_starvation_events" to pointcloudPoolStarvationEvents,
            "pool_starvation_event_count" to totalPoolStarvationEvents,
            "production_certified_mode_b" to productionCertifiedModeB,
            "arcoreFrameCount" to m.arcoreFrameCount.get(),
            "encodedVideoFrameCount" to m.encodedVideoFrameCount.get(),
            "submittedToEncoderFrameCount" to m.submittedToEncoderFrameCount.get(),
            "depthFrameCount" to m.depthFrameCount.get(),
            "pointCloudFrameCount" to m.pointCloudFrameCount.get(),
            "poseFrameCount" to m.poseFrameCount.get()
        )

        metadata["dataset_quality_summary"] = mapOf(
            "rgb_fps_effective" to encodedVideoFps,
            "depth_fps_effective" to depthFps,
            "rgb_depth_sync_rate" to rgbDepthSyncRate,
            "encoder_failure_rate" to encoderFailureRate,
            "max_timestamp_delta_ms" to (maxAssociationDeltaNs.toDouble() / 1_000_000.0),
            "memory_stable" to memoryStable,
            "memory_stable_long_window" to h.memoryStableLongWindow,
            "queue_stable" to queueStable,
            "pool_stable" to poolStable,
            "pool_high_watermark_ratio" to poolHighWatermarkRatio,
            "cumulative_frame_drift" to cumulativeFrameDrift,
            "drift_per_minute" to driftPerMinute,
            "drift_warning" to driftWarning,
            "drift_resync_event_count" to m.driftResyncEventCount,
            "production_certified_mode_b" to productionCertifiedModeB
        )

        metadata["encoder_queue_depth_after_fix"] = encoderQueueDepth
        metadata["max_encoder_queue_depth_after_fix"] = m.maxEncoderQueueDepth
        metadata["encoder_frame_interval_avg_ms"] = encoderFrameIntervalAvgMs
        metadata["encoder_frame_interval_std_ms"] = encoderFrameIntervalStdMs

        return FinalizationResult(
            metadata = metadata,
            associatedDepthFrames = associatedDepthFrames,
            unmatchedRgbFrames = unmatchedRgbFrames,
            missingDepthCount = missingDepthCount,
            maxAssociationDeltaNs = maxAssociationDeltaNs
        )
    }

    private fun estimatedArcoreFps(m: RecordingMetricsState): Double {
        if (m.arcoreCadenceSamples <= 0 || m.arcoreCadenceMeanIntervalNs <= 0.0) return 0.0
        return 1_000_000_000.0 / m.arcoreCadenceMeanIntervalNs
    }
}
