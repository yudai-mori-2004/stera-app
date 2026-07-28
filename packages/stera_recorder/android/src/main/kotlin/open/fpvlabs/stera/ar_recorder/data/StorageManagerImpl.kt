package open.fpvlabs.stera.ar_recorder.data

import java.io.File

/**
 * Handles storage headroom checks and dataset size projections.
 */
class StorageManagerImpl(
    private val safetyFactor: Double = 0.8,
    private val videoBitrateBitsPerSecond: Long = 10_000_000L,
    private val depthBytesPerSecondEstimate: Long = 2_500_000L,
    private val pointCloudBytesPerSecondEstimate: Long = 250_000L,
    private val csvLogBytesPerSecondEstimate: Long = 150_000L
) : StorageManager {

    override fun verifyHeadroom(
        baseDir: File,
        durationSeconds: Long,
        includeDepth: Boolean
    ): Pair<Boolean, String?> {
        val availableBytes = baseDir.usableSpace
        val estimatedBytes = estimateDatasetSize(durationSeconds, includeDepth)
        val thresholdBytes = (availableBytes.toDouble() * safetyFactor).toLong()
        if (estimatedBytes > thresholdBytes) {
            val message =
                "Insufficient storage headroom. Estimated $estimatedBytes bytes exceeds ${(safetyFactor * 100).toInt()}% of available storage $availableBytes bytes"
            return Pair(false, message)
        }
        return Pair(true, null)
    }

    override fun estimateDatasetSize(durationSeconds: Long, includeDepth: Boolean): Long {
        val videoBytes = (videoBitrateBitsPerSecond / 8L) * durationSeconds
        val depthBytes = if (includeDepth) depthBytesPerSecondEstimate * durationSeconds else 0L
        val pointCloudBytes = pointCloudBytesPerSecondEstimate * durationSeconds
        val logsBytes = csvLogBytesPerSecondEstimate * durationSeconds
        return videoBytes + depthBytes + pointCloudBytes + logsBytes
    }
}
