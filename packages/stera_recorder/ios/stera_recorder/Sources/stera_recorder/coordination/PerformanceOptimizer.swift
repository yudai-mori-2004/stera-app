import Foundation

class PerformanceOptimizer {

    struct BufferAuditResult {
        let shouldLog: Bool
        let nextAuditElapsedMs: Int64
    }

    struct DriftLogResult {
        let shouldLog: Bool
        let nextDriftLogElapsedMs: Int64
    }

    struct ParityFlags {
        let depthReleaseMismatchLogged: Bool
        let pointCloudReleaseMismatchLogged: Bool
        let depthReleaseOverAcquireLogged: Bool
        let pointCloudReleaseOverAcquireLogged: Bool
    }

    struct GcCleanupResult {
        let baselineMemoryUsageMb: Double?
        let lastMemoryUsageMb: Double?
        let memoryMonotonicGrowthStartMs: Int64
        let gcDropObservedInWindow: Bool
        let memoryBaselineResetCount: Int
        let memoryGrowthDetected: Bool
        let memoryGrowthConsecutiveMaintenanceCycles: Int
        let memoryStableMaintenanceCycles: Int
        let memoryStableSinceMs: Int64
        let memoryStableLongWindow: Bool
    }

    func evaluateBufferAudit(nowMs: Int64, lastBufferAuditElapsedMs: Int64, intervalMs: Int64) -> BufferAuditResult {
        if lastBufferAuditElapsedMs == 0 {
            return BufferAuditResult(shouldLog: false, nextAuditElapsedMs: nowMs)
        }
        if nowMs - lastBufferAuditElapsedMs < intervalMs {
            return BufferAuditResult(shouldLog: false, nextAuditElapsedMs: lastBufferAuditElapsedMs)
        }
        return BufferAuditResult(shouldLog: true, nextAuditElapsedMs: nowMs)
    }

    func evaluateDriftLog(nowMs: Int64, lastDriftLogElapsedMs: Int64, intervalMs: Int64) -> DriftLogResult {
        if lastDriftLogElapsedMs == 0 {
            return DriftLogResult(shouldLog: false, nextDriftLogElapsedMs: nowMs)
        }
        if nowMs - lastDriftLogElapsedMs < intervalMs {
            return DriftLogResult(shouldLog: false, nextDriftLogElapsedMs: lastDriftLogElapsedMs)
        }
        return DriftLogResult(shouldLog: true, nextDriftLogElapsedMs: nowMs)
    }

    func verifyResourceReleaseParity(
        depthAcquire: Int,
        depthClose: Int,
        pointAcquire: Int,
        pointRelease: Int,
        depthReleaseMismatchLogged: Bool,
        pointCloudReleaseMismatchLogged: Bool,
        depthReleaseOverAcquireLogged: Bool,
        pointCloudReleaseOverAcquireLogged: Bool,
        recordError: (String) -> Void
    ) -> ParityFlags {
        var depthMismatch = depthReleaseMismatchLogged
        var pointMismatch = pointCloudReleaseMismatchLogged
        var depthOverAcquire = depthReleaseOverAcquireLogged
        var pointOverAcquire = pointCloudReleaseOverAcquireLogged

        if depthAcquire != depthClose {
            if !depthMismatch {
                recordError("Depth acquire/close mismatch detected: acquire=\(depthAcquire) close=\(depthClose)")
                depthMismatch = true
            }
        } else {
            depthMismatch = false
        }
        if pointAcquire != pointRelease {
            if !pointMismatch {
                recordError("PointCloud acquire/release mismatch detected: acquire=\(pointAcquire) release=\(pointRelease)")
                pointMismatch = true
            }
        } else {
            pointMismatch = false
        }
        if depthClose > depthAcquire {
            if !depthOverAcquire {
                recordError("Depth close exceeded acquire count: acquire=\(depthAcquire) close=\(depthClose)")
                depthOverAcquire = true
            }
        } else {
            depthOverAcquire = false
        }
        if pointRelease > pointAcquire {
            if !pointOverAcquire {
                recordError("PointCloud release exceeded acquire count: acquire=\(pointAcquire) release=\(pointRelease)")
                pointOverAcquire = true
            }
        } else {
            pointOverAcquire = false
        }
        return ParityFlags(
            depthReleaseMismatchLogged: depthMismatch,
            pointCloudReleaseMismatchLogged: pointMismatch,
            depthReleaseOverAcquireLogged: depthOverAcquire,
            pointCloudReleaseOverAcquireLogged: pointOverAcquire
        )
    }

    func performGcFriendlyCleanup(
        currentMemoryUsageMb: Double,
        memoryBaselineResetCount: Int
    ) -> GcCleanupResult {
        return GcCleanupResult(
            baselineMemoryUsageMb: currentMemoryUsageMb,
            lastMemoryUsageMb: currentMemoryUsageMb,
            memoryMonotonicGrowthStartMs: 0,
            gcDropObservedInWindow: true,
            memoryBaselineResetCount: memoryBaselineResetCount + 1,
            memoryGrowthDetected: false,
            memoryGrowthConsecutiveMaintenanceCycles: 0,
            memoryStableMaintenanceCycles: 0,
            memoryStableSinceMs: Int64(Date().timeIntervalSince1970 * 1000),
            memoryStableLongWindow: false
        )
    }
}
