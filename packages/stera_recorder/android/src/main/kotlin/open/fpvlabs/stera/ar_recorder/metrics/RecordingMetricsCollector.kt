package open.fpvlabs.stera.ar_recorder.metrics

data class TimestampWindow(
    val minNs: Long,
    val maxNs: Long,
    val count: Long
)

data class AssociationStats(
    val associated: Int,
    val unmatched: Int,
    val maxDeltaNs: Long
)

interface RecordingMetricsCollector {
    fun computeDepthAssociations(
        rgbTimestamps: List<Long>,
        depthTimestamps: List<Long>,
        thresholdNs: Long
    ): AssociationStats

    fun computeStreamOverlap(ranges: List<TimestampWindow>): Boolean
}
