package open.fpvlabs.stera.ar_recorder.session

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import open.fpvlabs.stera.ar_recorder.ArTrackingState
import com.google.ar.core.ArCoreApk
import com.google.ar.core.CameraConfig
import com.google.ar.core.CameraConfigFilter
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import java.util.EnumSet

/**
 * Manages ARCore session lifecycle, availability checks, and configuration.
 */
class ArSessionManagerImpl(private val context: Context) : ArSessionManager {

    companion object {
        private const val MIN_STABLE_TRACKING_FRAMES = 10
        private const val SKIP_INITIAL_FRAMES = 30
        private const val TARGET_SENSOR_WIDTH = 1920
        private const val TARGET_SENSOR_HEIGHT = 1080
    }

    override var session: Session? = null
        private set

    override var isDepthSupported: Boolean = false
        private set

    override var isSessionReady: Boolean = false
        private set

    private var skippedFrames: Int = 0
    private var consecutiveTrackingFrames: Int = 0
    private var stableTrackingSinceMs: Long? = null

    override var selectedCameraResolution: String = "unknown"
        private set

    override var selectedFocusMode: String = "unknown"
        private set

    /**
     * Checks if ARCore is available on this device.
     */
    override fun checkAvailability(callback: (ArCoreApk.Availability) -> Unit) {
        ArCoreApk.getInstance().checkAvailabilityAsync(context) { availability ->
            callback(availability)
        }
    }

    /**
     * Creates and configures an ARCore session.
     * Must be called from an Activity with CAMERA permission.
     */
    @Throws(Exception::class)
    override fun createSession(activity: Activity) {
        if (session != null) {
            println("⚠️ ARCore session already exists")
            return
        }

        try {
            // Request ARCore installation if needed
            val availability = ArCoreApk.getInstance().requestInstall(activity, true)
            if (availability != ArCoreApk.InstallStatus.INSTALLED) {
                throw IllegalStateException("ARCore installation required")
            }

            // Create session
            session = Session(activity)
            println("✅ ARCore session created")

            // Prefer camera configs supporting 30 FPS for stable capture cadence.
            val sessionInstance = session ?: throw IllegalStateException("Session was not created")
            val fpsFilter = CameraConfigFilter(sessionInstance).setTargetFps(
                EnumSet.of(CameraConfig.TargetFps.TARGET_FPS_30)
            )
            val supportedConfigs = sessionInstance.getSupportedCameraConfigs(fpsFilter)
            if (supportedConfigs.isNotEmpty()) {
                val bestConfig = supportedConfigs.minWithOrNull(
                    compareBy<CameraConfig> {
                        val size = it.imageSize
                        kotlin.math.abs(size.width - TARGET_SENSOR_WIDTH) +
                            kotlin.math.abs(size.height - TARGET_SENSOR_HEIGHT)
                    }.thenByDescending { config ->
                        val size = config.imageSize
                        size.width * size.height
                    }
                ) ?: supportedConfigs.first()
                sessionInstance.cameraConfig = bestConfig
                val imageSize = sessionInstance.cameraConfig.imageSize
                selectedCameraResolution = "${imageSize.width}x${imageSize.height}"
                println("✅ Selected 30 FPS camera config: ${imageSize.width}x${imageSize.height}")
            } else {
                val fallbackConfig = sessionInstance.cameraConfig
                val fallbackSize = fallbackConfig.imageSize
                selectedCameraResolution = "${fallbackSize.width}x${fallbackSize.height}"
                println("⚠️ 30 FPS camera config unavailable, using fallback: ${fallbackSize.width}x${fallbackSize.height}")
            }

            // Configure session
            val config = Config(session).apply {
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                instantPlacementMode = Config.InstantPlacementMode.DISABLED
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL

                focusMode = Config.FocusMode.FIXED
                selectedFocusMode = Config.FocusMode.FIXED.name
                println("✅ Focus mode set: FIXED (autofocus disabled)")

                // Enable depth if supported
                if (session?.isDepthModeSupported(Config.DepthMode.AUTOMATIC) == true) {
                    depthMode = Config.DepthMode.AUTOMATIC
                    isDepthSupported = true
                    println("✅ Depth mode enabled")
                } else {
                    depthMode = Config.DepthMode.DISABLED
                    isDepthSupported = false
                    println("ℹ️ Depth mode not supported on this device")
                }
            }

            session?.configure(config)
            println("✅ ARCore session configured")

        } catch (e: Exception) {
            println("❌ Failed to create ARCore session: ${e.message}")
            e.printStackTrace()
            throw e
        }
    }

    /**
     * Resumes the ARCore session.
     */
    override fun resume() {
        try {
            session?.resume()
            println("✅ ARCore session resumed")
            skippedFrames = 0
            consecutiveTrackingFrames = 0
            isSessionReady = false
        } catch (e: Exception) {
            println("❌ Failed to resume ARCore session: ${e.message}")
            e.printStackTrace()
        }
    }

    /**
     * Pauses the ARCore session.
     */
    override fun pause() {
        try {
            session?.pause()
            println("✅ ARCore session paused")
        } catch (e: Exception) {
            println("❌ Failed to pause ARCore session: ${e.message}")
            e.printStackTrace()
        }
    }

    /**
     * Updates tracking state and returns whether session is ready for recording.
     * Must be called every frame from the AR frame loop.
     */
    override fun updateTrackingState(trackingState: TrackingState?): Boolean {
        if (!isTrackingStateValid(trackingState)) {
            consecutiveTrackingFrames = 0
            isSessionReady = false
            stableTrackingSinceMs = null
            return false
        }

        // Skip initial frames to allow stabilization
        if (skippedFrames < SKIP_INITIAL_FRAMES) {
            skippedFrames++
            return false
        }

        // Count consecutive tracking frames
        consecutiveTrackingFrames++

        // Session is ready when we have stable tracking
        val wasReady = isSessionReady
        isSessionReady = consecutiveTrackingFrames >= MIN_STABLE_TRACKING_FRAMES
        if (!wasReady && isSessionReady) {
            stableTrackingSinceMs = SystemClock.elapsedRealtime()
        }

        return isSessionReady
    }

    override fun hasStableTrackingFor(minDurationMs: Long): Boolean {
        if (!isSessionReady) return false
        val since = stableTrackingSinceMs ?: return false
        return (SystemClock.elapsedRealtime() - since) >= minDurationMs
    }

    /**
     * Checks if the current tracking state is valid (TRACKING).
     */
    private fun isTrackingStateValid(state: TrackingState?): Boolean {
        return state == TrackingState.TRACKING
    }

    /**
     * Gets the current tracking state as a string.
     */
    override fun getTrackingStateString(trackingState: TrackingState?): String {
        return ArTrackingState.fromArcoreState(trackingState).name
    }

    /**
     * Releases the ARCore session and all resources.
     */
    override fun release() {
        try {
            session?.close()
            session = null
            isSessionReady = false
            isDepthSupported = false
            skippedFrames = 0
            consecutiveTrackingFrames = 0
            stableTrackingSinceMs = null
            selectedCameraResolution = "unknown"
            selectedFocusMode = "unknown"
            println("✅ ARCore session released")
        } catch (e: Exception) {
            println("❌ Failed to release ARCore session: ${e.message}")
            e.printStackTrace()
        }
    }
}
