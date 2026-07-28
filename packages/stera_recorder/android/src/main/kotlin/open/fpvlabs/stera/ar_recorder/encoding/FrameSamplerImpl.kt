package open.fpvlabs.stera.ar_recorder.encoding

/**
 * Deterministic timestamp-based RGB frame sampler.
 */
class FrameSamplerImpl(
    private var targetFps: Int = 30
) : FrameSampler {
    private var encodeFrameIntervalNs: Long = 1_000_000_000L / targetFps
    private var sessionStartTimestampNs: Long = Long.MIN_VALUE
    private var deterministicFrameIndex: Long = 0L
    private var totalExpectedFrameCount: Long = 0L
    private var cumulativeTrackingPauseNs: Long = 0L

    override fun configure(targetFps: Int) {
        this.targetFps = targetFps.coerceAtLeast(1)
        this.encodeFrameIntervalNs = 1_000_000_000L / this.targetFps
    }

    override fun shouldEncodeFrame(timestampNs: Long): Boolean {
        if (sessionStartTimestampNs == Long.MIN_VALUE) {
            sessionStartTimestampNs = timestampNs
            deterministicFrameIndex = 0L
            totalExpectedFrameCount = 0L
        }
        val elapsedNs = (timestampNs - sessionStartTimestampNs - cumulativeTrackingPauseNs).coerceAtLeast(0L)
        val expectedFramesByNow = (elapsedNs / encodeFrameIntervalNs) + 1L
        if (expectedFramesByNow > totalExpectedFrameCount) {
            totalExpectedFrameCount = expectedFramesByNow
        }

        if (expectedFramesByNow <= deterministicFrameIndex) {
            return false
        }
        deterministicFrameIndex = expectedFramesByNow
        return true
    }

    override fun recordTrackingPauseOffset(offsetNs: Long) {
        cumulativeTrackingPauseNs += offsetNs.coerceAtLeast(0L)
    }

    override fun reset() {
        sessionStartTimestampNs = Long.MIN_VALUE
        deterministicFrameIndex = 0L
        totalExpectedFrameCount = 0L
        cumulativeTrackingPauseNs = 0L
    }

    override fun getDriftStats(): Map<String, Any> {
        return mapOf(
            "sessionStartTimestampNs" to sessionStartTimestampNs,
            "deterministicFrameIndex" to deterministicFrameIndex,
            "totalExpectedFrameCount" to totalExpectedFrameCount,
            "cumulativeTrackingPauseNs" to cumulativeTrackingPauseNs,
            "targetFps" to targetFps,
            "encodeFrameIntervalNs" to encodeFrameIntervalNs
        )
    }
}
