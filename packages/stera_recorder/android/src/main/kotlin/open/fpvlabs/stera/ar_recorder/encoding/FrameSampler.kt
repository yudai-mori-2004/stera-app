package open.fpvlabs.stera.ar_recorder.encoding

interface FrameSampler {
    fun configure(targetFps: Int)

    fun shouldEncodeFrame(timestampNs: Long): Boolean

    fun recordTrackingPauseOffset(offsetNs: Long)

    fun reset()

    fun getDriftStats(): Map<String, Any>
}
