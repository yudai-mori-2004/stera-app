package open.fpvlabs.stera.ar_recorder.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Collects accelerometer and gyroscope data from device sensors.
 * Buffers the latest reading from each sensor and emits combined samples
 * containing both accel and gyro values.
 */
class ImuCollectorImpl(private val context: Context) : ImuCollector, SensorEventListener {

    companion object {
        private const val SENSOR_RATE = SensorManager.SENSOR_DELAY_FASTEST
    }

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null

    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null

    private val sampleQueue = ConcurrentLinkedQueue<ImuSample>()

    private var isCollecting: Boolean = false

    // Latest readings for pairing
    @Volatile private var latestAccelX: Float = 0f
    @Volatile private var latestAccelY: Float = 0f
    @Volatile private var latestAccelZ: Float = 0f
    @Volatile private var hasAccel: Boolean = false

    @Volatile private var latestGyroX: Float = 0f
    @Volatile private var latestGyroY: Float = 0f
    @Volatile private var latestGyroZ: Float = 0f
    @Volatile private var hasGyro: Boolean = false

    @Volatile
    private var firstTimestampNs: Long? = null
    @Volatile
    private var lastTimestampNs: Long? = null
    @Volatile
    private var totalCallbackLatencyNs: Long = 0L
    @Volatile
    private var maxCallbackLatencyNs: Long = 0L
    @Volatile
    private var callbackCount: Long = 0L

    override fun initialize(): Boolean {
        try {
            sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

            if (sensorManager == null) {
                println("❌ SensorManager not available")
                return false
            }

            accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            gyroscope = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

            if (accelerometer == null) {
                println("⚠️ Accelerometer not available")
            }

            if (gyroscope == null) {
                println("⚠️ Gyroscope not available")
            }

            if (accelerometer == null && gyroscope == null) {
                println("❌ No IMU sensors available")
                return false
            }

            handlerThread = HandlerThread("ArImuThread").apply { start() }
            handler = Handler(handlerThread!!.looper)

            println("✅ IMU collector initialized")
            return true

        } catch (e: Exception) {
            println("❌ Failed to initialize IMU collector: ${e.message}")
            e.printStackTrace()
            return false
        }
    }

    override fun start() {
        if (isCollecting) return

        try {
            sampleQueue.clear()
            firstTimestampNs = null
            lastTimestampNs = null
            totalCallbackLatencyNs = 0L
            maxCallbackLatencyNs = 0L
            callbackCount = 0L
            hasAccel = false
            hasGyro = false

            accelerometer?.let { sensor ->
                sensorManager?.registerListener(this, sensor, SENSOR_RATE, handler)
            }

            gyroscope?.let { sensor ->
                sensorManager?.registerListener(this, sensor, SENSOR_RATE, handler)
            }

            isCollecting = true
            println("✅ IMU collection started")

        } catch (e: Exception) {
            println("❌ Failed to start IMU collection: ${e.message}")
            e.printStackTrace()
        }
    }

    override fun stop() {
        if (!isCollecting) return

        try {
            sensorManager?.unregisterListener(this)
            isCollecting = false
            println("✅ IMU collection stopped")
        } catch (e: Exception) {
            println("❌ Failed to stop IMU collection: ${e.message}")
            e.printStackTrace()
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event?.let {
            when (it.sensor.type) {
                Sensor.TYPE_ACCELEROMETER -> {
                    latestAccelX = it.values[0]
                    latestAccelY = it.values[1]
                    latestAccelZ = it.values[2]
                    hasAccel = true
                }
                Sensor.TYPE_GYROSCOPE -> {
                    latestGyroX = it.values[0]
                    latestGyroY = it.values[1]
                    latestGyroZ = it.values[2]
                    hasGyro = true
                }
                else -> return
            }

            // Only emit combined samples once both sensors have reported
            if (!hasAccel || !hasGyro) return

            val callbackNowNs = SystemClock.elapsedRealtimeNanos()
            val callbackLatencyNs = callbackNowNs - it.timestamp

            val sample = ImuSample(
                timestampNs = it.timestamp,
                accelX = latestAccelX,
                accelY = latestAccelY,
                accelZ = latestAccelZ,
                gyroX = latestGyroX,
                gyroY = latestGyroY,
                gyroZ = latestGyroZ,
                callbackLatencyNs = callbackLatencyNs
            )

            sampleQueue.offer(sample)
            firstTimestampNs = firstTimestampNs ?: it.timestamp
            lastTimestampNs = it.timestamp
            callbackCount++
            totalCallbackLatencyNs += callbackLatencyNs
            if (callbackLatencyNs > maxCallbackLatencyNs) {
                maxCallbackLatencyNs = callbackLatencyNs
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not used
    }

    override fun drainSamples(): List<ImuSample> {
        val samples = mutableListOf<ImuSample>()
        while (true) {
            val sample = sampleQueue.poll() ?: break
            samples.add(sample)
        }
        return samples
    }

    override fun getQueueSize(): Int = sampleQueue.size

    override fun getFirstTimestampNs(): Long? = firstTimestampNs

    override fun getLastTimestampNs(): Long? = lastTimestampNs

    override fun getAverageCallbackLatencyNs(): Double {
        return if (callbackCount == 0L) 0.0 else totalCallbackLatencyNs.toDouble() / callbackCount.toDouble()
    }

    override fun getMaxCallbackLatencyNs(): Long = maxCallbackLatencyNs

    override fun getCallbackCount(): Long = callbackCount

    override fun release() {
        stop()
        sampleQueue.clear()

        handlerThread?.quitSafely()
        try {
            handlerThread?.join()
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
        handlerThread = null
        handler = null

        sensorManager = null
        accelerometer = null
        gyroscope = null

        println("✅ IMU collector released")
    }
}
