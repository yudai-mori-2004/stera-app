package open.fpvlabs.stera.ar_recorder.coordination

import android.os.Handler
import android.os.SystemClock
import open.fpvlabs.stera.ar_recorder.data.DatasetWriter
import open.fpvlabs.stera.ar_recorder.encoding.EglManager
import open.fpvlabs.stera.ar_recorder.metrics.PerformanceMonitor
import open.fpvlabs.stera.ar_recorder.session.ArFrameProcessor
import kotlin.math.max

/**
 * Owns all runtime health-monitoring state and the periodic maintenance/health-sampling
 * logic that was previously inline in ArRecorderImpl.
 *
 * Responsibilities:
 * - Periodic health sampling (FPS drift, memory growth, thermal status)
 * - Periodic maintenance (encoder drain, bitrate adjustment, pool audits)
 * - Encoder backpressure enforcement
 * - Resource release parity verification
 * - GC-friendly cleanup
 * - Size projection warnings
 */
class RuntimeHealthManager(
    private val metrics: RecordingMetricsState,
    private val healthMonitor: RecordingHealthMonitor,
    private val performanceOptimizer: PerformanceOptimizer,
    private val videoEncodingCoordinator: VideoEncodingCoordinator,
    private val frameProcessingCoordinator: FrameProcessingCoordinator,
    private val frameProcessor: ArFrameProcessor,
    private val eglManager: EglManager,
    private val performanceMonitor: PerformanceMonitor,
    private val datasetWriter: DatasetWriter,
    private val recordError: (String, Throwable?) -> Unit
) {
    companion object {
        private const val HEALTH_SAMPLE_INTERVAL_MS = 5000L
        private const val PERIODIC_MAINTENANCE_INTERVAL_MS = 30_000L
        private const val BUFFER_AUDIT_INTERVAL_MS = 120_000L
        private const val DRIFT_LOG_INTERVAL_MS = 60_000L
        private const val SIZE_WARNING_THRESHOLD_BYTES = 2L * 1024L * 1024L * 1024L
        private const val FPS_DRIFT_THRESHOLD = 1.0
        private const val MEMORY_GROWTH_WARN_RATIO = 0.10
        private const val ENCODER_QUEUE_SOFT_LIMIT = 2
        private const val ENCODER_QUEUE_HARD_LIMIT = 5
        private const val BITRATE_REDUCTION_TRIGGER_QUEUE_DEPTH = 3
        private const val BITRATE_RESTORE_STABLE_WINDOW_MS = 20_000L
        private const val BITRATE_ADJUSTMENT_STEP_PERCENT = 10
        private const val LEAK_MONOTONIC_WINDOW_MS = 120_000L
        private const val GC_DROP_RESET_RATIO = 0.30
        private const val MEMORY_GROWTH_SUSTAINED_MAINTENANCE_CYCLES = 3
        private const val MEMORY_STABLE_LONG_WINDOW_MS = 180_000L
        private const val THERMAL_BITRATE_CLAMP_STATUS = 1
        private const val VIDEO_BITRATE_FALLBACK = 8_000_000
        private const val DEVICE_METRICS_REFRESH_INTERVAL_MS = 500L
    }

    // ── Writer handler for thread-safe MCAP writes ──────────────────────
    @Volatile
    var writerHandler: Handler? = null

    // ── Device metrics cache (refreshed ~500ms, written per-frame ~15Hz) ──
    data class CachedDeviceMetrics(
        var batteryLevel: Float = 0f,
        var batteryState: Int = 0,
        var batteryStateStr: String = "unknown",
        var cpuUsage: Float = 0f,
        var memoryUsedMb: Double = 0.0,
        var memoryAvailableMb: Double = 0.0,
        var thermalState: Int = 0,
        var thermalStateStr: String = "unavailable"
    )
    @Volatile
    var cachedDeviceMetrics = CachedDeviceMetrics()
    private var lastDeviceMetricsRefreshMs: Long = 0L

    // ── Health sampling state ────────────────────────────────────────────
    var lastHealthSampleElapsedMs: Long = 0L
    var lastHealthSampleArcoreFrames: Int = 0
    var lastHealthSampleEncodedFrames: Int = 0
    var thermalThrottlingDetected: Boolean = false
    var fpsDriftDetected: Boolean = false
    var memoryGrowthDetected: Boolean = false
    var maxMemoryUsageMb: Double = 0.0
    var maxNativeHeapMb: Double = 0.0
    var maxDirectBufferMbEstimate: Double = 0.0
    var leakSuspected: Boolean = false
    var lastMemoryUsageMb: Double? = null
    var baselineMemoryUsageMb: Double? = null

    // ── Memory leak detection ────────────────────────────────────────────
    var memoryMonotonicGrowthStartMs: Long = 0L
    var gcDropObservedInWindow: Boolean = false
    var memoryBaselineResetCount: Int = 0
    var memoryGrowthConsecutiveMaintenanceCycles: Int = 0
    var memoryStableMaintenanceCycles: Int = 0
    var memoryStableSinceMs: Long = 0L
    var memoryStableLongWindow: Boolean = false
    var memoryHighWatermarkMb: Double = 0.0

    // ── Periodic maintenance state ───────────────────────────────────────
    var lastMaintenanceElapsedMs: Long = 0L
    var maintenanceCycleCount: Int = 0
    var maintenanceForcedDrainCount: Int = 0
    var maintenanceLastEncoderQueueDepth: Int = 0
    var lastBufferAuditElapsedMs: Long = 0L
    var lastDriftLogElapsedMs: Long = 0L
    var lastDepthCadenceResetCountAtMaintenance: Int = 0
    var lastBitrateAdjustmentCountAtMaintenance: Int = 0

    // ── Resource parity flags ────────────────────────────────────────────
    var depthReleaseMismatchLogged: Boolean = false
    var pointCloudReleaseMismatchLogged: Boolean = false
    var depthReleaseOverAcquireLogged: Boolean = false
    var pointCloudReleaseOverAcquireLogged: Boolean = false

    // ── Thermal state ────────────────────────────────────────────────────
    var lastThermalStatusCode: Int? = null
    var lastThermalStatusLabel: String = "unavailable"
    var thermalStatusLabel: String = "unavailable"
    var thermalStateTransitionCount: Int = 0
    var thermalBitrateClampActive: Boolean = false
    var thermalClampAppliedCount: Int = 0
    var thermalClampReleasedCount: Int = 0

    /**
     * Resets all health manager state for a new recording session.
     */
    fun reset() {
        lastHealthSampleElapsedMs = 0L
        lastHealthSampleArcoreFrames = 0
        lastHealthSampleEncodedFrames = 0
        thermalThrottlingDetected = false
        fpsDriftDetected = false
        memoryGrowthDetected = false
        maxMemoryUsageMb = 0.0
        maxNativeHeapMb = 0.0
        maxDirectBufferMbEstimate = 0.0
        leakSuspected = false
        lastMemoryUsageMb = null
        baselineMemoryUsageMb = null
        memoryMonotonicGrowthStartMs = 0L
        gcDropObservedInWindow = false
        memoryBaselineResetCount = 0
        memoryGrowthConsecutiveMaintenanceCycles = 0
        memoryStableMaintenanceCycles = 0
        memoryStableSinceMs = 0L
        memoryStableLongWindow = false
        memoryHighWatermarkMb = 0.0
        lastMaintenanceElapsedMs = 0L
        maintenanceCycleCount = 0
        maintenanceForcedDrainCount = 0
        maintenanceLastEncoderQueueDepth = 0
        lastBufferAuditElapsedMs = 0L
        lastDriftLogElapsedMs = 0L
        lastDepthCadenceResetCountAtMaintenance = 0
        lastBitrateAdjustmentCountAtMaintenance = 0
        depthReleaseMismatchLogged = false
        pointCloudReleaseMismatchLogged = false
        depthReleaseOverAcquireLogged = false
        pointCloudReleaseOverAcquireLogged = false
        lastThermalStatusCode = null
        lastThermalStatusLabel = "unavailable"
        thermalStatusLabel = "unavailable"
        thermalStateTransitionCount = 0
        thermalBitrateClampActive = false
        thermalClampAppliedCount = 0
        thermalClampReleasedCount = 0
        performanceMonitor.reset()
    }

    // ── Encoder backpressure ─────────────────────────────────────────────

    /**
     * Enforces encoder backpressure by draining the encoder when the queue
     * exceeds the soft limit. Returns the queue depth after enforcement.
     */
    fun enforceEncoderBackpressure(queueDepth: Int): Int {
        if (queueDepth <= ENCODER_QUEUE_SOFT_LIMIT) {
            return queueDepth
        }

        metrics.encoderBackpressureDetected = true
        drainEncoder(endOfStream = false)

        var depthAfterDrain = metrics.encoderQueueDepth()
        if (depthAfterDrain > ENCODER_QUEUE_HARD_LIMIT) {
            drainEncoder(endOfStream = false)
            depthAfterDrain = metrics.encoderQueueDepth()
            if (depthAfterDrain > ENCODER_QUEUE_HARD_LIMIT) {
                recordError(
                    "Encoder queue exceeded hard limit: depth=$depthAfterDrain limit=$ENCODER_QUEUE_HARD_LIMIT",
                    null
                )
            }
        }

        return depthAfterDrain
    }

    // ── Resource release parity ──────────────────────────────────────────

    /** Verifies depth/pointcloud acquire and release counts match. */
    fun verifyResourceReleaseParity() {
        val depthAcquire = frameProcessor.getDepthImageAcquireCount()
        val depthClose = frameProcessor.getDepthImageCloseCount()
        val pointAcquire = frameProcessor.getPointCloudAcquireCount()
        val pointRelease = frameProcessor.getPointCloudReleaseCount()
        val parity = performanceOptimizer.verifyResourceReleaseParity(
            depthAcquire = depthAcquire,
            depthClose = depthClose,
            pointAcquire = pointAcquire,
            pointRelease = pointRelease,
            depthReleaseMismatchLogged = depthReleaseMismatchLogged,
            pointCloudReleaseMismatchLogged = pointCloudReleaseMismatchLogged,
            depthReleaseOverAcquireLogged = depthReleaseOverAcquireLogged,
            pointCloudReleaseOverAcquireLogged = pointCloudReleaseOverAcquireLogged,
            recordError = { message -> recordError(message, null) }
        )
        depthReleaseMismatchLogged = parity.depthReleaseMismatchLogged
        pointCloudReleaseMismatchLogged = parity.pointCloudReleaseMismatchLogged
        depthReleaseOverAcquireLogged = parity.depthReleaseOverAcquireLogged
        pointCloudReleaseOverAcquireLogged = parity.pointCloudReleaseOverAcquireLogged
    }

    // ── Periodic health sampling ─────────────────────────────────────────

    /** Samples runtime health metrics (FPS, memory, thermal). */
    fun maybeSampleRuntimeHealth() {
        performanceMonitor.sampleHealth()
        val nowMs = SystemClock.elapsedRealtime()
        if (lastHealthSampleElapsedMs == 0L) {
            lastHealthSampleElapsedMs = nowMs
            lastHealthSampleArcoreFrames = metrics.arcoreFrameCount.get()
            lastHealthSampleEncodedFrames = metrics.encodedVideoFrameCount.get()
            baselineMemoryUsageMb = currentMemoryUsageMb()
            maxMemoryUsageMb = baselineMemoryUsageMb ?: 0.0
            memoryHighWatermarkMb = baselineMemoryUsageMb ?: 0.0
            maxNativeHeapMb = currentNativeHeapUsageMb()
            maxDirectBufferMbEstimate = currentDirectBufferUsageMbEstimate()
            lastMemoryUsageMb = baselineMemoryUsageMb
            return
        }

        val elapsedMs = nowMs - lastHealthSampleElapsedMs
        if (elapsedMs < HEALTH_SAMPLE_INTERVAL_MS) {
            return
        }

        val arcoreDelta = metrics.arcoreFrameCount.get() - lastHealthSampleArcoreFrames
        val encodedDelta = metrics.encodedVideoFrameCount.get() - lastHealthSampleEncodedFrames
        val elapsedSec = elapsedMs / 1000.0
        val arcoreFpsWindow = if (elapsedSec > 0) arcoreDelta.toDouble() / elapsedSec else 0.0
        val encodedFpsWindow = if (elapsedSec > 0) encodedDelta.toDouble() / elapsedSec else 0.0

        fpsDriftDetected = kotlin.math.abs(encodedFpsWindow - metrics.targetEncodeFps.toDouble()) > FPS_DRIFT_THRESHOLD

        val memoryUsageMb = currentMemoryUsageMb()
        val nativeHeapMb = currentNativeHeapUsageMb()
        val directBufferMbEstimate = currentDirectBufferUsageMbEstimate()
        if (memoryUsageMb > maxMemoryUsageMb) maxMemoryUsageMb = memoryUsageMb
        if (memoryUsageMb > memoryHighWatermarkMb) memoryHighWatermarkMb = memoryUsageMb
        if (nativeHeapMb > maxNativeHeapMb) maxNativeHeapMb = nativeHeapMb
        if (directBufferMbEstimate > maxDirectBufferMbEstimate) maxDirectBufferMbEstimate = directBufferMbEstimate

        val previous = lastMemoryUsageMb
        if (previous != null && previous > 0.0) {
            val dropRatio = (previous - memoryUsageMb) / previous
            if (dropRatio >= GC_DROP_RESET_RATIO) {
                gcDropObservedInWindow = true
                memoryMonotonicGrowthStartMs = 0L
                baselineMemoryUsageMb = memoryUsageMb
                memoryBaselineResetCount++
                leakSuspected = false
                datasetWriter.logSystem(
                    "Memory baseline reset after drop. previous_mb=${"%.2f".format(previous)} current_mb=${"%.2f".format(memoryUsageMb)}"
                )
            } else if (memoryUsageMb > previous) {
                if (memoryMonotonicGrowthStartMs == 0L) {
                    memoryMonotonicGrowthStartMs = nowMs
                    gcDropObservedInWindow = false
                } else if (!gcDropObservedInWindow && nowMs - memoryMonotonicGrowthStartMs >= LEAK_MONOTONIC_WINDOW_MS && !leakSuspected) {
                    leakSuspected = true
                    datasetWriter.logSystem(
                        "WARN: leak suspected due to monotonic growth > ${LEAK_MONOTONIC_WINDOW_MS}ms without GC drop"
                    )
                }
            } else {
                memoryMonotonicGrowthStartMs = 0L
                if (memoryUsageMb < previous) {
                    gcDropObservedInWindow = true
                }
            }
        }
        lastMemoryUsageMb = memoryUsageMb

        val thermalStatus = readThermalStatus()
        thermalStatusLabel = thermalStatus.label
        if (thermalStatus.throttling) {
            thermalThrottlingDetected = true
        }
        handleThermalStatus(nowMs, thermalStatus)

        if (fpsDriftDetected) {
            datasetWriter.logSystem(
                "WARN: encoded FPS drift detected. encoded=${"%.2f".format(encodedFpsWindow)} target=${metrics.targetEncodeFps} thermal=${thermalStatus.label}"
            )
        }

        datasetWriter.logSystem(
            "Health sample: arcore_fps_window=${"%.2f".format(arcoreFpsWindow)} encoded_fps_window=${"%.2f".format(encodedFpsWindow)} " +
                "memory_mb=${"%.2f".format(memoryUsageMb)} native_heap_mb=${"%.2f".format(nativeHeapMb)} " +
                "direct_buffer_mb_est=${"%.2f".format(directBufferMbEstimate)} encoder_queue_depth=${metrics.encoderQueueDepthAfterFix} target_encode_fps=${metrics.targetEncodeFps} mode=${metrics.dynamicEncoderMode} thermal=${thermalStatus.label}"
        )

        lastHealthSampleElapsedMs = nowMs
        lastHealthSampleArcoreFrames = metrics.arcoreFrameCount.get()
        lastHealthSampleEncodedFrames = metrics.encodedVideoFrameCount.get()
    }

    // ── Periodic maintenance ─────────────────────────────────────────────

    /** Runs periodic maintenance: encoder drain, bitrate adjustment, pool/memory checks. */
    fun maybeRunPeriodicMaintenance() {
        val nowMs = SystemClock.elapsedRealtime()
        if (lastMaintenanceElapsedMs == 0L) {
            lastMaintenanceElapsedMs = nowMs
            lastBufferAuditElapsedMs = nowMs
            lastDriftLogElapsedMs = nowMs
            return
        }

        if (nowMs - lastMaintenanceElapsedMs < PERIODIC_MAINTENANCE_INTERVAL_MS) {
            return
        }

        maintenanceCycleCount++
        maintenanceForcedDrainCount++
        drainEncoder(endOfStream = false)
        maintenanceLastEncoderQueueDepth = metrics.encoderQueueDepth()
        maybeAdjustEncoderBitrate(nowMs, maintenanceLastEncoderQueueDepth)

        verifyResourceReleaseParity()

        val depthStarvationEvents = frameProcessor.getDepthPoolStarvationEvents()
        val pointcloudStarvationEvents = frameProcessor.getPointCloudPoolStarvationEvents()
        metrics.poolStarvationEventCount = depthStarvationEvents + pointcloudStarvationEvents

        val depthPoolCapacity = frameProcessor.getDepthPoolCapacity().coerceAtLeast(1)
        val pointCloudPoolCapacity = frameProcessor.getPointCloudPoolCapacity().coerceAtLeast(1)
        val depthPoolHighWatermarkRatio = frameProcessor.getDepthPoolMaxInUse().toDouble() / depthPoolCapacity.toDouble()
        val pointCloudPoolHighWatermarkRatio = frameProcessor.getPointCloudPoolMaxInUse().toDouble() / pointCloudPoolCapacity.toDouble()
        val poolHighWatermarkRatio = max(depthPoolHighWatermarkRatio, pointCloudPoolHighWatermarkRatio)
        if (poolHighWatermarkRatio > 0.85) {
            datasetWriter.logSystem(
                "WARN: pool nearing starvation. pool_high_watermark_ratio=${"%.3f".format(poolHighWatermarkRatio)} depth_ratio=${"%.3f".format(depthPoolHighWatermarkRatio)} pointcloud_ratio=${"%.3f".format(pointCloudPoolHighWatermarkRatio)}"
            )
        }

        val memoryNowMb = currentMemoryUsageMb()
        if (memoryNowMb > memoryHighWatermarkMb) {
            memoryHighWatermarkMb = memoryNowMb
        }
        val baselineMb = baselineMemoryUsageMb ?: memoryNowMb
        val memoryGrowthRatio = if (baselineMb > 0.0) (memoryNowMb - baselineMb) / baselineMb else 0.0
        val bitrateAdjustmentCount = metrics.bitrateReducedCount + metrics.bitrateRestoreCount + thermalClampAppliedCount + thermalClampReleasedCount
        val ignoreMemoryGrowthCycle =
            metrics.depthCadenceResetCount != lastDepthCadenceResetCountAtMaintenance ||
                bitrateAdjustmentCount != lastBitrateAdjustmentCountAtMaintenance

        if (memoryGrowthRatio > MEMORY_GROWTH_WARN_RATIO && !ignoreMemoryGrowthCycle) {
            memoryGrowthConsecutiveMaintenanceCycles++
            if (memoryGrowthConsecutiveMaintenanceCycles >= MEMORY_GROWTH_SUSTAINED_MAINTENANCE_CYCLES) {
                if (!memoryGrowthDetected) {
                    datasetWriter.logSystem(
                        "WARN: sustained memory growth across maintenance cycles. baseline_mb=${"%.2f".format(baselineMb)} current_mb=${"%.2f".format(memoryNowMb)} growth_ratio=${"%.3f".format(memoryGrowthRatio)} cycles=$memoryGrowthConsecutiveMaintenanceCycles"
                    )
                }
                memoryGrowthDetected = true
            }
        } else {
            memoryGrowthConsecutiveMaintenanceCycles = 0
            if (memoryGrowthRatio <= MEMORY_GROWTH_WARN_RATIO) {
                memoryGrowthDetected = false
            }
        }

        if (ignoreMemoryGrowthCycle && memoryGrowthRatio > MEMORY_GROWTH_WARN_RATIO) {
            datasetWriter.logSystem(
                "Memory growth spike ignored for this maintenance cycle due to cadence/bitrate transition"
            )
        }

        val memoryStableNow = !memoryGrowthDetected && !leakSuspected &&
            (ignoreMemoryGrowthCycle || memoryGrowthRatio <= MEMORY_GROWTH_WARN_RATIO)
        if (memoryStableNow) {
            memoryStableMaintenanceCycles++
            if (memoryStableSinceMs == 0L) {
                memoryStableSinceMs = nowMs
            }
            if (nowMs - memoryStableSinceMs >= MEMORY_STABLE_LONG_WINDOW_MS ||
                memoryStableMaintenanceCycles >= MEMORY_GROWTH_SUSTAINED_MAINTENANCE_CYCLES
            ) {
                memoryStableLongWindow = true
            }
        } else {
            memoryStableMaintenanceCycles = 0
            memoryStableSinceMs = 0L
            memoryStableLongWindow = false
        }

        lastDepthCadenceResetCountAtMaintenance = metrics.depthCadenceResetCount
        lastBitrateAdjustmentCountAtMaintenance = bitrateAdjustmentCount

        if (memoryGrowthDetected) {
            performGcFriendlyCleanup()
        }

        maybeRunBufferAudit(nowMs)
        maybeLogCumulativeDrift(nowMs)

        datasetWriter.logSystem(
            "Maintenance cycle #$maintenanceCycleCount: encoder_queue_depth=$maintenanceLastEncoderQueueDepth " +
                "egl_preview_surface=${eglManager.hasPreviewSurface()} egl_encoder_surface=${eglManager.hasEncoderSurface()} " +
                "depth_pool_min_available=${frameProcessor.getDepthPoolMinAvailable()} " +
                "depth_pool_max_in_use=${frameProcessor.getDepthPoolMaxInUse()} " +
                "pointcloud_pool_min_available=${frameProcessor.getPointCloudPoolMinAvailable()} " +
                "pointcloud_pool_max_in_use=${frameProcessor.getPointCloudPoolMaxInUse()} " +
                "depth_pool_high_watermark_ratio=${"%.3f".format(depthPoolHighWatermarkRatio)} " +
                "pointcloud_pool_high_watermark_ratio=${"%.3f".format(pointCloudPoolHighWatermarkRatio)} " +
                "pool_high_watermark_ratio=${"%.3f".format(poolHighWatermarkRatio)} " +
                "memory_mb=${"%.2f".format(memoryNowMb)} memory_growth_ratio=${"%.3f".format(memoryGrowthRatio)} " +
                "memory_growth_cycles=$memoryGrowthConsecutiveMaintenanceCycles memory_stable_cycles=$memoryStableMaintenanceCycles memory_stable_long_window=$memoryStableLongWindow " +
                "pool_starvation_events=${metrics.poolStarvationEventCount}"
        )

        lastMaintenanceElapsedMs = nowMs
    }

    // ── Size projection ──────────────────────────────────────────────────

    /** Logs a warning if projected dataset size exceeds the threshold. */
    fun maybeLogSizeProjection(recordingStartTime: Long, estimateProjectionBytes: (Long) -> Long) {
        if (metrics.sizeWarningLogged) return
        val elapsedMs = System.currentTimeMillis() - recordingStartTime
        if (elapsedMs < 2000L) return
        val projectedBytes = estimateProjectionBytes(elapsedMs)
        if (projectedBytes > SIZE_WARNING_THRESHOLD_BYTES) {
            datasetWriter.logSystem(
                "WARN: projected dataset size exceeds threshold. projected=$projectedBytes threshold=$SIZE_WARNING_THRESHOLD_BYTES"
            )
            metrics.sizeWarningLogged = true
        }
    }

    // ── Internal helpers ─────────────────────────────────────────────────

    private fun currentMemoryUsageMb(): Double = healthMonitor.currentMemoryUsageMb()

    private fun currentNativeHeapUsageMb(): Double = healthMonitor.currentNativeHeapUsageMb()

    private fun currentDirectBufferUsageMbEstimate(): Double {
        val glBytes = eglManager.getDirectBufferUsageEstimateBytes()
        return healthMonitor.currentDirectBufferUsageMbEstimate(glBytes)
    }

    private data class ThermalSnapshot(
        val label: String,
        val statusCode: Int?,
        val throttling: Boolean,
        val shouldClampBitrate: Boolean
    )

    private fun readThermalStatus(): ThermalSnapshot {
        val snapshot = healthMonitor.readThermalStatus(THERMAL_BITRATE_CLAMP_STATUS)
        return ThermalSnapshot(
            label = snapshot.label,
            statusCode = snapshot.statusCode,
            throttling = snapshot.throttling,
            shouldClampBitrate = snapshot.shouldClampBitrate
        )
    }

    private fun handleThermalStatus(nowMs: Long, thermalStatus: ThermalSnapshot) {
        val transition = healthMonitor.updateThermalTransition(
            nowMs = nowMs,
            thermalStatus = RecordingHealthMonitor.ThermalSnapshot(
                label = thermalStatus.label,
                statusCode = thermalStatus.statusCode,
                throttling = thermalStatus.throttling,
                shouldClampBitrate = thermalStatus.shouldClampBitrate
            ),
            lastThermalStatusCode = lastThermalStatusCode,
            lastThermalStatusLabel = lastThermalStatusLabel,
            thermalStateTransitionCount = thermalStateTransitionCount,
            logSystem = { message -> datasetWriter.logSystem(message) }
        )
        lastThermalStatusCode = transition.lastThermalStatusCode
        lastThermalStatusLabel = transition.lastThermalStatusLabel ?: "unavailable"
        thermalStateTransitionCount = transition.thermalStateTransitionCount

        if (thermalStatus.shouldClampBitrate && !thermalBitrateClampActive) {
            thermalBitrateClampActive = true
            if (metrics.activeVideoBitrate > VIDEO_BITRATE_FALLBACK && applyEncoderBitrate(VIDEO_BITRATE_FALLBACK)) {
                thermalClampAppliedCount++
            }
            datasetWriter.logSystem("Thermal clamp active: forcing bitrate to $VIDEO_BITRATE_FALLBACK")
            return
        }

        if (!thermalStatus.shouldClampBitrate && thermalBitrateClampActive) {
            thermalBitrateClampActive = false
            if (metrics.activeVideoBitrate < metrics.targetVideoBitrate && applyEncoderBitrate(metrics.targetVideoBitrate)) {
                thermalClampReleasedCount++
            }
            datasetWriter.logSystem("Thermal clamp released: restoring bitrate toward target=${metrics.targetVideoBitrate}")
        }
    }

    private fun performGcFriendlyCleanup() {
        drainEncoder(endOfStream = false)
        System.gc()
        val cleanup = performanceOptimizer.performGcFriendlyCleanup(
            currentMemoryUsageMb = currentMemoryUsageMb(),
            memoryBaselineResetCount = memoryBaselineResetCount
        )
        baselineMemoryUsageMb = cleanup.baselineMemoryUsageMb
        lastMemoryUsageMb = cleanup.lastMemoryUsageMb
        memoryMonotonicGrowthStartMs = cleanup.memoryMonotonicGrowthStartMs
        gcDropObservedInWindow = cleanup.gcDropObservedInWindow
        memoryBaselineResetCount = cleanup.memoryBaselineResetCount
        memoryGrowthDetected = cleanup.memoryGrowthDetected
        memoryGrowthConsecutiveMaintenanceCycles = cleanup.memoryGrowthConsecutiveMaintenanceCycles
        memoryStableMaintenanceCycles = cleanup.memoryStableMaintenanceCycles
        memoryStableSinceMs = cleanup.memoryStableSinceMs
        memoryStableLongWindow = cleanup.memoryStableLongWindow
        datasetWriter.logSystem("GC-friendly cleanup executed; memory baseline reset")
    }

    private fun maybeRunBufferAudit(nowMs: Long) {
        val audit = performanceOptimizer.evaluateBufferAudit(
            nowMs = nowMs,
            lastBufferAuditElapsedMs = lastBufferAuditElapsedMs,
            intervalMs = BUFFER_AUDIT_INTERVAL_MS
        )
        lastBufferAuditElapsedMs = audit.nextAuditElapsedMs
        if (!audit.shouldLog) return

        val depthAcquire = frameProcessor.getDepthImageAcquireCount()
        val depthClose = frameProcessor.getDepthImageCloseCount()
        val pointAcquire = frameProcessor.getPointCloudAcquireCount()
        val pointRelease = frameProcessor.getPointCloudReleaseCount()
        val parityOk = depthAcquire == depthClose && pointAcquire == pointRelease
        datasetWriter.logSystem(
            "Buffer audit: depth_acquire=$depthAcquire depth_close=$depthClose pointcloud_acquire=$pointAcquire pointcloud_release=$pointRelease parity_ok=$parityOk"
        )
    }

    private fun maybeLogCumulativeDrift(nowMs: Long) {
        val drift = performanceOptimizer.evaluateDriftLog(
            nowMs = nowMs,
            lastDriftLogElapsedMs = lastDriftLogElapsedMs,
            intervalMs = DRIFT_LOG_INTERVAL_MS
        )
        lastDriftLogElapsedMs = drift.nextDriftLogElapsedMs
        if (!drift.shouldLog) return

        val encodedFrames = metrics.encodedVideoFrameCount.get().toLong()
        val driftFrames = (metrics.totalExpectedFrameCount - encodedFrames).coerceAtLeast(0L)
        val elapsedMinutes = (nowMs - lastMaintenanceElapsedMs).coerceAtLeast(1L) / 60_000.0
        val driftPerMinute = if (elapsedMinutes > 0.0) driftFrames.toDouble() / elapsedMinutes else 0.0
        val driftWarning = driftPerMinute > 10.0
        datasetWriter.logSystem(
            "Cumulative drift: expected_frames=${metrics.totalExpectedFrameCount} encoded_frames=$encodedFrames drift_frames=$driftFrames drift_per_minute=${"%.3f".format(driftPerMinute)} drift_warning=$driftWarning"
        )
    }

    private fun maybeAdjustEncoderBitrate(nowMs: Long, queueDepth: Int) {
        val result = videoEncodingCoordinator.maybeAdjustEncoderBitrate(
            nowMs = nowMs,
            queueDepth = queueDepth,
            thermalBitrateClampActive = thermalBitrateClampActive,
            activeVideoBitrate = metrics.activeVideoBitrate,
            targetVideoBitrate = metrics.targetVideoBitrate,
            bitrateStableSinceMs = metrics.bitrateStableSinceMs,
            bitrateReducedCount = metrics.bitrateReducedCount,
            bitrateRestoreCount = metrics.bitrateRestoreCount,
            videoBitrateFallback = VIDEO_BITRATE_FALLBACK,
            encoderQueueSoftLimit = ENCODER_QUEUE_SOFT_LIMIT,
            bitrateReductionTriggerQueueDepth = BITRATE_REDUCTION_TRIGGER_QUEUE_DEPTH,
            bitrateRestoreStableWindowMs = BITRATE_RESTORE_STABLE_WINDOW_MS,
            bitrateAdjustmentStepPercent = BITRATE_ADJUSTMENT_STEP_PERCENT
        )
        metrics.activeVideoBitrate = result.activeVideoBitrate
        metrics.bitrateStableSinceMs = result.bitrateStableSinceMs
        metrics.bitrateReducedCount = result.bitrateReducedCount
        metrics.bitrateRestoreCount = result.bitrateRestoreCount
    }

    private fun applyEncoderBitrate(newBitrate: Int): Boolean {
        val updated = videoEncodingCoordinator.applyEncoderBitrate(newBitrate) ?: return false
        metrics.activeVideoBitrate = updated
        return true
    }

    private fun drainEncoder(endOfStream: Boolean) {
        val result = videoEncodingCoordinator.drainVideoEncoder(
            endOfStream = endOfStream,
            configuredVideoWidth = metrics.configuredVideoWidth,
            configuredVideoHeight = metrics.configuredVideoHeight,
            targetEncodeFps = metrics.targetEncodeFps
        )
        metrics.actualVideoWidth = result.actualVideoWidth
        metrics.actualVideoHeight = result.actualVideoHeight
    }

    // ── Device Metrics (per-frame write + periodic cache refresh) ──────

    /** Refreshes cached device metrics if the refresh interval has elapsed. */
    fun maybeRefreshDeviceMetricsCache() {
        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - lastDeviceMetricsRefreshMs < DEVICE_METRICS_REFRESH_INTERVAL_MS && lastDeviceMetricsRefreshMs != 0L) {
            return
        }
        val battery = healthMonitor.readBatteryInfo()
        val cpuUsage = healthMonitor.readCpuUsage()
        val memoryMb = currentMemoryUsageMb()
        val availableMemMb = healthMonitor.availableMemoryMb()
        val thermalStatus = readThermalStatus()
        cachedDeviceMetrics = CachedDeviceMetrics(
            batteryLevel = battery.level,
            batteryState = battery.state,
            batteryStateStr = battery.stateStr,
            cpuUsage = cpuUsage,
            memoryUsedMb = memoryMb,
            memoryAvailableMb = availableMemMb,
            thermalState = thermalStatus.statusCode ?: 0,
            thermalStateStr = thermalStatus.label
        )
        lastDeviceMetricsRefreshMs = nowMs
    }

    /** Writes cached device metrics to MCAP. Must be called on the writerHandler thread. */
    fun writeDeviceMetricsForFrame(timestampNs: Long) {
        val m = cachedDeviceMetrics
        datasetWriter.writeDeviceMetrics(
            timestampNs = timestampNs,
            batteryLevel = m.batteryLevel,
            batteryState = m.batteryState,
            batteryStateStr = m.batteryStateStr,
            cpuUsage = m.cpuUsage,
            memoryUsedMb = m.memoryUsedMb,
            memoryAvailableMb = m.memoryAvailableMb,
            thermalState = m.thermalState,
            thermalStateStr = m.thermalStateStr
        )
    }
}
