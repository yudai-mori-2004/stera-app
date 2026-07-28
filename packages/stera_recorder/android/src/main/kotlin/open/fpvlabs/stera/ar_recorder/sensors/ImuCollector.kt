package open.fpvlabs.stera.ar_recorder.sensors

data class ImuSample(
    val timestampNs: Long,
    val accelX: Float,
    val accelY: Float,
    val accelZ: Float,
    val gyroX: Float,
    val gyroY: Float,
    val gyroZ: Float,
    val callbackLatencyNs: Long
)

interface ImuCollector {
    fun initialize(): Boolean
    fun start()
    fun stop()
    fun drainSamples(): List<ImuSample>
    fun getQueueSize(): Int
    fun getFirstTimestampNs(): Long?
    fun getLastTimestampNs(): Long?
    fun getAverageCallbackLatencyNs(): Double
    fun getMaxCallbackLatencyNs(): Long
    fun getCallbackCount(): Long
    fun release()
}
