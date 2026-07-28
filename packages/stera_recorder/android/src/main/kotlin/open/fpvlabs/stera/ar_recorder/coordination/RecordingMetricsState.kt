package open.fpvlabs.stera.ar_recorder.coordination

import java.util.concurrent.atomic.AtomicInteger

/**
 * Owns all per-recording mutable counters, timestamp tracking, and frame index lists.
 * Provides a single [reset] method to reinitialize everything between recordings.
 *
 * This class consolidates the ~100 mutable state fields that were previously
 * scattered across ArRecorderImpl, making them easy to inspect, test, and reset.
 */
class RecordingMetricsState {

    // ── Timestamp range tracker ──────────────────────────────────────────
    class TimestampRange(
        var minNs: Long = Long.MAX_VALUE,
        var maxNs: Long = Long.MIN_VALUE,
        var count: Long = 0L
    ) {
        fun record(timestampNs: Long) {
            if (timestampNs < minNs) minNs = timestampNs
            if (timestampNs > maxNs) maxNs = timestampNs
            count++
        }

        fun startOrZero(): Long = if (count > 0) minNs else 0L
        fun endOrZero(): Long = if (count > 0) maxNs else 0L
        fun durationNsOrZero(): Long = if (count > 1) maxNs - minNs else 0L

        fun reset() {
            minNs = Long.MAX_VALUE
            maxNs = Long.MIN_VALUE
            count = 0L
        }
    }

    companion object {
        const val MAX_TIMESTAMP_HISTORY = 500_000
    }

    // ── Atomic frame counters ────────────────────────────────────────────
    val arcoreFrameCount = AtomicInteger(0)
    val encodedVideoFrameCount = AtomicInteger(0)
    val submittedToEncoderFrameCount = AtomicInteger(0)
    val depthFrameCount = AtomicInteger(0)
    val pointCloudFrameCount = AtomicInteger(0)
    val poseFrameCount = AtomicInteger(0)
    val droppedFrameCount = AtomicInteger(0)
    val skippedDepthFrameCount = AtomicInteger(0)

    // ── Scalar counters ──────────────────────────────────────────────────
    var trackingLossEvents: Int = 0
    var sizeWarningLogged: Boolean = false
    var frameCount: Int = 0
    var globalArFrameIndex: Int = 0

    // ── Timestamp ranges ─────────────────────────────────────────────────
    val rgbTimestampRange = TimestampRange()
    val poseTimestampRange = TimestampRange()
    val depthTimestampRange = TimestampRange()
    val pointCloudTimestampRange = TimestampRange()
    val imuTimestampRange = TimestampRange()

    // ── Timestamp history deques ─────────────────────────────────────────
    val rgbFrameTimestamps = ArrayDeque<Long>(MAX_TIMESTAMP_HISTORY)
    val depthFrameTimestamps = ArrayDeque<Long>(MAX_TIMESTAMP_HISTORY)
    val depthAssociationCandidateRgbTimestamps = ArrayDeque<Long>(MAX_TIMESTAMP_HISTORY)

    // ── Frame index tracking lists ───────────────────────────────────────
    val rgbEncodedFrameIndices = mutableListOf<Int>()
    val rgbEncoderFailureFrameIndices = mutableListOf<Int>()
    val depthFrameIndices = mutableListOf<Int>()
    val depthDroppedFrameIndices = mutableListOf<Int>()
    val pointcloudFrameIndices = mutableListOf<Int>()
    val pointcloudDroppedFrameIndices = mutableListOf<Int>()
    val poseDroppedFrameIndices = mutableListOf<Int>()

    // ── Render loop performance ──────────────────────────────────────────
    var renderLoopIterations: Long = 0L
    var renderLoopTotalNs: Long = 0L

    // ── Encoder queue ────────────────────────────────────────────────────
    var maxEncoderQueueDepth: Int = 0

    // ── Depth acquisition latency ────────────────────────────────────────
    var depthAcquisitionSamples: Int = 0
    var depthAcquisitionTotalLatencyNs: Long = 0L
    var depthAcquisitionMaxLatencyNs: Long = 0L

    // ── Error tracking ───────────────────────────────────────────────────
    var totalErrorsEncountered: Int = 0

    // ── Tracking pause / depth cadence ───────────────────────────────────
    var trackingPauseDepthSkipCount: Int = 0
    var depthAttemptCount: Int = 0
    var depthSuccessCount: Int = 0
    var depthCadenceResetCount: Int = 0
    var wasTrackingInPreviousFrame: Boolean = false

    // ── Tracking pause offset ────────────────────────────────────────────
    var trackingPauseCount: Int = 0
    var trackingPauseTotalOffsetNs: Long = 0L
    var trackingPausedAtNs: Long = Long.MIN_VALUE

    // ── Video encoder state ──────────────────────────────────────────────
    var encoderSurfaceReady: Boolean = false
    var lastEncodedTimestampNs: Long = Long.MIN_VALUE
    var lastSubmittedTimestampNs: Long = Long.MIN_VALUE
    var sessionStartTimestampNs: Long = Long.MIN_VALUE
    var deterministicFrameIndex: Long = 0L
    var totalExpectedFrameCount: Long = 0L
    var configuredVideoWidth: Int = 720
    var configuredVideoHeight: Int = 1280
    var actualVideoWidth: Int = 0
    var actualVideoHeight: Int = 0

    // ── Encoder interval statistics (Welford online) ─────────────────────
    var encoderIntervalSamples: Long = 0L
    var encoderIntervalMeanNs: Double = 0.0
    var encoderIntervalM2Ns: Double = 0.0

    // ── ARCore cadence estimation (Welford online) ───────────────────────
    var lastArcoreTimestampNsForEstimate: Long = Long.MIN_VALUE
    var arcoreCadenceSamples: Long = 0L
    var arcoreCadenceMeanIntervalNs: Double = 0.0
    var arcoreCadenceM2IntervalNs: Double = 0.0

    // ── RGB sampling / encoder failures ──────────────────────────────────
    var rgbSamplingSkippedCount: Int = 0
    var rgbEncoderFailureCount: Int = 0
    var lastObservedArcoreTimestampNs: Long = Long.MIN_VALUE
    var driftResyncEventCount: Int = 0
    var pointCloudSoftSkipCount: Int = 0

    // ── Encoder backpressure ─────────────────────────────────────────────
    var encoderBackpressureDetected: Boolean = false
    var poolStarvationEventCount: Int = 0
    var encoderQueueDepthAfterFix: Int = 0

    // ── Bitrate adaptation ───────────────────────────────────────────────
    var targetEncodeFps: Int = 30
    var targetVideoBitrate: Int = 10_000_000
    var activeVideoBitrate: Int = 10_000_000
    var bitrateReducedCount: Int = 0
    var bitrateRestoreCount: Int = 0
    var bitrateStableSinceMs: Long = 0L
    var encodeFrameIntervalNs: Long = 1_000_000_000L / 30
    var dynamicEncoderMode: String = "deterministic_30fps_sampling"

    // ── Depth association threshold ──────────────────────────────────────
    var effectiveDepthAssociationThresholdNs: Long = 40_000_000L

    /** Adds a timestamp to the deque, evicting the oldest if at capacity. */
    fun addTimestampWithCap(store: ArrayDeque<Long>, timestampNs: Long) {
        if (store.size >= MAX_TIMESTAMP_HISTORY) {
            store.removeFirst()
        }
        store.addLast(timestampNs)
    }

    /** The current encoder queue depth (submitted minus encoded). */
    fun encoderQueueDepth(): Int =
        (submittedToEncoderFrameCount.get() - encodedVideoFrameCount.get()).coerceAtLeast(0)

    /**
     * Resets all metrics for a new recording session.
     */
    fun reset(
        defaultVideoWidth: Int = 720,
        defaultVideoHeight: Int = 1280,
        sensorWidth: Int = 1920,
        sensorHeight: Int = 1080,
        defaultBitrate: Int = 10_000_000,
        defaultFps: Int = 30,
        depthAssociationThresholdNs: Long = 40_000_000L
    ) {
        arcoreFrameCount.set(0)
        encodedVideoFrameCount.set(0)
        submittedToEncoderFrameCount.set(0)
        depthFrameCount.set(0)
        pointCloudFrameCount.set(0)
        poseFrameCount.set(0)
        droppedFrameCount.set(0)
        skippedDepthFrameCount.set(0)

        trackingLossEvents = 0
        sizeWarningLogged = false
        frameCount = 0
        globalArFrameIndex = 0

        rgbTimestampRange.reset()
        poseTimestampRange.reset()
        depthTimestampRange.reset()
        pointCloudTimestampRange.reset()
        imuTimestampRange.reset()

        rgbFrameTimestamps.clear()
        depthFrameTimestamps.clear()
        depthAssociationCandidateRgbTimestamps.clear()

        rgbEncodedFrameIndices.clear()
        rgbEncoderFailureFrameIndices.clear()
        depthFrameIndices.clear()
        depthDroppedFrameIndices.clear()
        pointcloudFrameIndices.clear()
        pointcloudDroppedFrameIndices.clear()
        poseDroppedFrameIndices.clear()

        renderLoopIterations = 0L
        renderLoopTotalNs = 0L
        maxEncoderQueueDepth = 0
        depthAcquisitionSamples = 0
        depthAcquisitionTotalLatencyNs = 0L
        depthAcquisitionMaxLatencyNs = 0L
        totalErrorsEncountered = 0
        trackingPauseDepthSkipCount = 0
        depthAttemptCount = 0
        depthSuccessCount = 0
        depthCadenceResetCount = 0
        wasTrackingInPreviousFrame = false
        trackingPauseCount = 0
        trackingPauseTotalOffsetNs = 0L
        trackingPausedAtNs = Long.MIN_VALUE

        configuredVideoWidth = defaultVideoWidth
        configuredVideoHeight = defaultVideoHeight
        actualVideoWidth = 0
        actualVideoHeight = 0
        encoderSurfaceReady = false
        lastEncodedTimestampNs = Long.MIN_VALUE
        lastSubmittedTimestampNs = Long.MIN_VALUE
        sessionStartTimestampNs = Long.MIN_VALUE
        deterministicFrameIndex = 0L
        totalExpectedFrameCount = 0L
        encoderIntervalSamples = 0L
        encoderIntervalMeanNs = 0.0
        encoderIntervalM2Ns = 0.0

        lastArcoreTimestampNsForEstimate = Long.MIN_VALUE
        arcoreCadenceSamples = 0L
        arcoreCadenceMeanIntervalNs = 0.0
        arcoreCadenceM2IntervalNs = 0.0

        rgbSamplingSkippedCount = 0
        rgbEncoderFailureCount = 0
        lastObservedArcoreTimestampNs = Long.MIN_VALUE
        driftResyncEventCount = 0
        pointCloudSoftSkipCount = 0

        encoderBackpressureDetected = false
        poolStarvationEventCount = 0
        encoderQueueDepthAfterFix = 0

        targetEncodeFps = defaultFps
        targetVideoBitrate = defaultBitrate
        activeVideoBitrate = defaultBitrate
        bitrateReducedCount = 0
        bitrateRestoreCount = 0
        bitrateStableSinceMs = 0L
        encodeFrameIntervalNs = 1_000_000_000L / defaultFps
        dynamicEncoderMode = "deterministic_30fps_sampling"

        effectiveDepthAssociationThresholdNs = depthAssociationThresholdNs
    }
}
