package open.fpvlabs.stera.ar_recorder.metrics

import android.os.SystemClock

/**
 * Lightweight runtime performance monitor.
 *
 * Keeps memory and cadence snapshots centralized so ArRecorderImpl stays focused
 * on orchestration.
 */
class PerformanceMonitorImpl : PerformanceMonitor {
    private var maxMemoryUsageMb: Double = 0.0
    private var lastMemoryUsageMb: Double = 0.0
    private var lastSampleElapsedMs: Long = 0L

    override fun reset() {
        maxMemoryUsageMb = 0.0
        lastMemoryUsageMb = 0.0
        lastSampleElapsedMs = 0L
    }

    override fun sampleHealth(): Map<String, Any> {
        val runtime = Runtime.getRuntime()
        val usedBytes = runtime.totalMemory() - runtime.freeMemory()
        val memoryMb = usedBytes.toDouble() / (1024.0 * 1024.0)
        if (memoryMb > maxMemoryUsageMb) {
            maxMemoryUsageMb = memoryMb
        }
        val nowMs = SystemClock.elapsedRealtime()
        val elapsedMs = if (lastSampleElapsedMs == 0L) 0L else nowMs - lastSampleElapsedMs
        val previous = lastMemoryUsageMb
        lastMemoryUsageMb = memoryMb
        lastSampleElapsedMs = nowMs

        return mapOf(
            "memoryMb" to memoryMb,
            "maxMemoryMb" to maxMemoryUsageMb,
            "elapsedMsSinceLastSample" to elapsedMs,
            "deltaMemoryMb" to (memoryMb - previous)
        )
    }

    override fun getPerformanceMetrics(): Map<String, Any> {
        return mapOf(
            "maxMemoryUsageMb" to maxMemoryUsageMb,
            "lastMemoryUsageMb" to lastMemoryUsageMb
        )
    }
}
