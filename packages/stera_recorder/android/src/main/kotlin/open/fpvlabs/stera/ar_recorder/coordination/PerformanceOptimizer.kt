package open.fpvlabs.stera.ar_recorder.coordination

class PerformanceOptimizer {
    data class BufferAuditResult(val shouldLog: Boolean, val nextAuditElapsedMs: Long)
    data class DriftLogResult(val shouldLog: Boolean, val nextDriftLogElapsedMs: Long)
    data class ParityFlags(
        val depthReleaseMismatchLogged: Boolean,
        val pointCloudReleaseMismatchLogged: Boolean,
        val depthReleaseOverAcquireLogged: Boolean,
        val pointCloudReleaseOverAcquireLogged: Boolean
    )
    data class GcCleanupResult(
        val baselineMemoryUsageMb: Double?,
        val lastMemoryUsageMb: Double?,
        val memoryMonotonicGrowthStartMs: Long,
        val gcDropObservedInWindow: Boolean,
        val memoryBaselineResetCount: Int,
        val memoryGrowthDetected: Boolean,
        val memoryGrowthConsecutiveMaintenanceCycles: Int,
        val memoryStableMaintenanceCycles: Int,
        val memoryStableSinceMs: Long,
        val memoryStableLongWindow: Boolean
    )

    fun evaluateBufferAudit(nowMs: Long, lastBufferAuditElapsedMs: Long, intervalMs: Long): BufferAuditResult {
        if (lastBufferAuditElapsedMs == 0L) {
            return BufferAuditResult(shouldLog = false, nextAuditElapsedMs = nowMs)
        }
        if (nowMs - lastBufferAuditElapsedMs < intervalMs) {
            return BufferAuditResult(shouldLog = false, nextAuditElapsedMs = lastBufferAuditElapsedMs)
        }
        return BufferAuditResult(shouldLog = true, nextAuditElapsedMs = nowMs)
    }

    fun evaluateDriftLog(nowMs: Long, lastDriftLogElapsedMs: Long, intervalMs: Long): DriftLogResult {
        if (lastDriftLogElapsedMs == 0L) {
            return DriftLogResult(shouldLog = false, nextDriftLogElapsedMs = nowMs)
        }
        if (nowMs - lastDriftLogElapsedMs < intervalMs) {
            return DriftLogResult(shouldLog = false, nextDriftLogElapsedMs = lastDriftLogElapsedMs)
        }
        return DriftLogResult(shouldLog = true, nextDriftLogElapsedMs = nowMs)
    }

    fun verifyResourceReleaseParity(
        depthAcquire: Int,
        depthClose: Int,
        pointAcquire: Int,
        pointRelease: Int,
        depthReleaseMismatchLogged: Boolean,
        pointCloudReleaseMismatchLogged: Boolean,
        depthReleaseOverAcquireLogged: Boolean,
        pointCloudReleaseOverAcquireLogged: Boolean,
        recordError: (String) -> Unit
    ): ParityFlags {
        var depthMismatch = depthReleaseMismatchLogged
        var pointMismatch = pointCloudReleaseMismatchLogged
        var depthOverAcquire = depthReleaseOverAcquireLogged
        var pointOverAcquire = pointCloudReleaseOverAcquireLogged

        if (depthAcquire != depthClose) {
            if (!depthMismatch) {
                recordError("Depth acquire/close mismatch detected: acquire=$depthAcquire close=$depthClose")
                depthMismatch = true
            }
        } else {
            depthMismatch = false
        }
        if (pointAcquire != pointRelease) {
            if (!pointMismatch) {
                recordError("PointCloud acquire/release mismatch detected: acquire=$pointAcquire release=$pointRelease")
                pointMismatch = true
            }
        } else {
            pointMismatch = false
        }
        if (depthClose > depthAcquire) {
            if (!depthOverAcquire) {
                recordError("Depth close exceeded acquire count: acquire=$depthAcquire close=$depthClose")
                depthOverAcquire = true
            }
        } else {
            depthOverAcquire = false
        }
        if (pointRelease > pointAcquire) {
            if (!pointOverAcquire) {
                recordError("PointCloud release exceeded acquire count: acquire=$pointAcquire release=$pointRelease")
                pointOverAcquire = true
            }
        } else {
            pointOverAcquire = false
        }
        return ParityFlags(depthMismatch, pointMismatch, depthOverAcquire, pointOverAcquire)
    }

    fun performGcFriendlyCleanup(
        currentMemoryUsageMb: Double,
        memoryBaselineResetCount: Int
    ): GcCleanupResult {
        return GcCleanupResult(
            baselineMemoryUsageMb = currentMemoryUsageMb,
            lastMemoryUsageMb = currentMemoryUsageMb,
            memoryMonotonicGrowthStartMs = 0L,
            gcDropObservedInWindow = true,
            memoryBaselineResetCount = memoryBaselineResetCount + 1,
            memoryGrowthDetected = false,
            memoryGrowthConsecutiveMaintenanceCycles = 0,
            memoryStableMaintenanceCycles = 0,
            memoryStableSinceMs = System.currentTimeMillis(),
            memoryStableLongWindow = false
        )
    }
}
