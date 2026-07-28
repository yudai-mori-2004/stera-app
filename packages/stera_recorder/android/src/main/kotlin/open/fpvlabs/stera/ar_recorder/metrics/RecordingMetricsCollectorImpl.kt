package open.fpvlabs.stera.ar_recorder.metrics

import kotlin.math.abs
import kotlin.math.min

/**
 * Focused collector for association/overlap computations used at stop time.
 */
class RecordingMetricsCollectorImpl : RecordingMetricsCollector {
    override fun computeDepthAssociations(
        rgbTimestamps: List<Long>,
        depthTimestamps: List<Long>,
        thresholdNs: Long
    ): AssociationStats {
        if (rgbTimestamps.isEmpty() || depthTimestamps.isEmpty()) {
            return AssociationStats(associated = 0, unmatched = rgbTimestamps.size, maxDeltaNs = 0L)
        }

        val sortedDepth = depthTimestamps.sorted()
        var associated = 0
        var maxDeltaNs = 0L

        for (rgbTs in rgbTimestamps) {
            val index = sortedDepth.binarySearch(rgbTs)
            val insertionPoint = if (index >= 0) index else -(index + 1)

            var nearestDelta = Long.MAX_VALUE
            if (insertionPoint < sortedDepth.size) {
                nearestDelta = min(nearestDelta, abs(sortedDepth[insertionPoint] - rgbTs))
            }
            if (insertionPoint > 0) {
                nearestDelta = min(nearestDelta, abs(sortedDepth[insertionPoint - 1] - rgbTs))
            }

            if (nearestDelta <= thresholdNs) {
                associated++
                if (nearestDelta > maxDeltaNs) {
                    maxDeltaNs = nearestDelta
                }
            }
        }

        return AssociationStats(
            associated = associated,
            unmatched = rgbTimestamps.size - associated,
            maxDeltaNs = maxDeltaNs
        )
    }

    override fun computeStreamOverlap(ranges: List<TimestampWindow>): Boolean {
        val validRanges = ranges.filter { it.count > 0 }
        if (validRanges.isEmpty()) return false
        val latestStart = validRanges.maxOf { it.minNs }
        val earliestEnd = validRanges.minOf { it.maxNs }
        return latestStart <= earliestEnd
    }
}
