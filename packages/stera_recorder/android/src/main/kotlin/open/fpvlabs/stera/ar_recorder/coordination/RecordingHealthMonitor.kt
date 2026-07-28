package open.fpvlabs.stera.ar_recorder.coordination

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import java.io.File

class RecordingHealthMonitor(
    private val context: Context
) {
    data class ThermalSnapshot(
        val label: String,
        val statusCode: Int?,
        val throttling: Boolean,
        val shouldClampBitrate: Boolean
    )

    data class ThermalTransitionResult(
        val transitioned: Boolean,
        val lastThermalStatusCode: Int?,
        val lastThermalStatusLabel: String?,
        val thermalStateTransitionCount: Int
    )

    fun currentMemoryUsageMb(): Double {
        val runtime = Runtime.getRuntime()
        val usedBytes = runtime.totalMemory() - runtime.freeMemory()
        return usedBytes.toDouble() / (1024.0 * 1024.0)
    }

    fun currentNativeHeapUsageMb(): Double {
        return Debug.getNativeHeapAllocatedSize().toDouble() / (1024.0 * 1024.0)
    }

    fun currentDirectBufferUsageMbEstimate(eglDirectBufferBytes: Long): Double {
        val uvBytes = (8L * 4L) * 2L
        return (uvBytes + eglDirectBufferBytes).toDouble() / (1024.0 * 1024.0)
    }

    fun readThermalStatus(thermalBitrateClampStatus: Int): ThermalSnapshot {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (powerManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val status = powerManager.currentThermalStatus
            val throttling = status >= PowerManager.THERMAL_STATUS_SEVERE
            return ThermalSnapshot(
                label = "status_$status",
                statusCode = status,
                throttling = throttling,
                shouldClampBitrate = status >= thermalBitrateClampStatus
            )
        }
        val sysTemp = readCpuTemperatureFromSysfs()
        return if (sysTemp != null) {
            val throttling = sysTemp >= 75.0
            val derivedStatus = when {
                sysTemp >= 80.0 -> 4
                sysTemp >= 75.0 -> 3
                sysTemp >= 70.0 -> 2
                sysTemp >= 65.0 -> 1
                else -> 0
            }
            ThermalSnapshot(
                label = "cpu_temp_${"%.1f".format(sysTemp)}C",
                statusCode = derivedStatus,
                throttling = throttling,
                shouldClampBitrate = derivedStatus >= thermalBitrateClampStatus
            )
        } else {
            ThermalSnapshot(
                label = "unavailable",
                statusCode = null,
                throttling = false,
                shouldClampBitrate = false
            )
        }
    }

    fun updateThermalTransition(
        nowMs: Long,
        thermalStatus: ThermalSnapshot,
        lastThermalStatusCode: Int?,
        lastThermalStatusLabel: String?,
        thermalStateTransitionCount: Int,
        logSystem: (String) -> Unit
    ): ThermalTransitionResult {
        if (lastThermalStatusCode != thermalStatus.statusCode || lastThermalStatusLabel != thermalStatus.label) {
            val count = thermalStateTransitionCount + 1
            logSystem("Thermal transition @${nowMs}ms: ${lastThermalStatusLabel} -> ${thermalStatus.label}")
            return ThermalTransitionResult(
                transitioned = true,
                lastThermalStatusCode = thermalStatus.statusCode,
                lastThermalStatusLabel = thermalStatus.label,
                thermalStateTransitionCount = count
            )
        }
        return ThermalTransitionResult(
            transitioned = false,
            lastThermalStatusCode = lastThermalStatusCode,
            lastThermalStatusLabel = lastThermalStatusLabel,
            thermalStateTransitionCount = thermalStateTransitionCount
        )
    }

    // ── Battery ──────────────────────────────────────────────────────────

    data class BatteryInfo(val level: Float, val state: Int, val stateStr: String)

    fun readBatteryInfo(): BatteryInfo {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent != null) {
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val pct = if (level >= 0 && scale > 0) (level.toFloat() / scale.toFloat()) * 100f else 0f
            val (state, stateStr) = when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING -> 2 to "charging"
                BatteryManager.BATTERY_STATUS_FULL -> 3 to "full"
                BatteryManager.BATTERY_STATUS_DISCHARGING,
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> 1 to "unplugged"
                else -> 0 to "unknown"
            }
            return BatteryInfo(pct, state, stateStr)
        }
        return BatteryInfo(0f, 0, "unknown")
    }

    // ── CPU Usage ───────────────────────────────────────────────────────

    @Volatile
    private var lastCpuTimeMs: Long = 0L
    @Volatile
    private var lastWallTimeMs: Long = 0L

    fun readCpuUsage(): Float {
        val cpuTimeMs = Process.getElapsedCpuTime()
        val wallTimeMs = SystemClock.elapsedRealtime()
        val prevCpu = lastCpuTimeMs
        val prevWall = lastWallTimeMs
        lastCpuTimeMs = cpuTimeMs
        lastWallTimeMs = wallTimeMs
        if (prevWall == 0L || wallTimeMs <= prevWall) return 0f
        val deltaCpu = (cpuTimeMs - prevCpu).toFloat()
        val deltaWall = (wallTimeMs - prevWall).toFloat()
        return ((deltaCpu / deltaWall) * 100f).coerceIn(0f, 100f * Runtime.getRuntime().availableProcessors())
    }

    // ── Available Memory ────────────────────────────────────────────────

    fun availableMemoryMb(): Double {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return 0.0
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)
        return memInfo.availMem.toDouble() / (1024.0 * 1024.0)
    }

    private fun readCpuTemperatureFromSysfs(): Double? {
        return try {
            val thermalRoot = File("/sys/class/thermal")
            val zones = thermalRoot.listFiles { file -> file.name.startsWith("thermal_zone") } ?: return null
            var best: Double? = null
            for (zone in zones) {
                val tempFile = File(zone, "temp")
                if (!tempFile.exists()) continue
                val raw = tempFile.readText().trim().toDoubleOrNull() ?: continue
                val celsius = if (raw > 1000.0) raw / 1000.0 else raw
                if (best == null || celsius > best) {
                    best = celsius
                }
            }
            best
        } catch (_: Exception) {
            null
        }
    }
}
