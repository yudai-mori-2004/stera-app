package open.fpvlabs.stera.ar_recorder.metrics

interface PerformanceMonitor {
    fun reset()
    fun sampleHealth(): Map<String, Any>
    fun getPerformanceMetrics(): Map<String, Any>
}
