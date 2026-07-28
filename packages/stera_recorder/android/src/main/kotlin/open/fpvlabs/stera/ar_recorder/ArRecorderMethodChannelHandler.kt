package open.fpvlabs.stera.ar_recorder

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Handles Flutter MethodChannel calls for AR recording operations.
 */
class ArRecorderMethodChannelHandler(
    private val activity: Activity,
    binaryMessenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry
) {

    companion object {
        private const val CHANNEL_NAME = "ar_recorder"
    }

    private val arRecorder: ArRecorder = ArRecorderImpl(activity, textureRegistry)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val controlExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private val methodChannel: MethodChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeSession" -> handleInitializeSession(call, result)
                "startRecording" -> handleStartRecording(call, result)
                "pauseRecording" -> handlePauseRecording(result)
                "resumeRecording" -> handleResumeRecording(result)
                "cancelRecording" -> handleCancelRecording(result)
                "stopRecording" -> handleStopRecording(result)
                "getRecordingState" -> handleGetRecordingState(result)
                "checkArAvailability" -> handleCheckArAvailability(result)
                "disposeSession" -> handleDisposeSession(result)
                else -> result.notImplemented()
            }
        }
        println("✅ ArRecorderMethodChannelHandler initialized")
    }

    /**
     * Handles initializeSession method call.
     * Must run on main thread because textureRegistry.createSurfaceTexture() requires a Looper.
     */
    private fun handleInitializeSession(call: MethodCall, result: MethodChannel.Result) {
        try {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val response = arRecorder.initializeSession(call.arguments)
            result.success(response)
        } catch (e: Exception) {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            e.printStackTrace()
            result.error(
                "INITIALIZATION_ERROR",
                e.message ?: "Failed to initialize AR session",
                null
            )
        }
    }

    /**
     * Handles startRecording method call.
     */
    private fun handleStartRecording(call: MethodCall, result: MethodChannel.Result) {
        runBackgroundAction(
            action = { arRecorder.startRecording(call.arguments) },
            errorCode = "START_RECORDING_ERROR",
            errorMessage = "Failed to start recording",
            result = result
        )
    }

    private fun handlePauseRecording(result: MethodChannel.Result) {
        runBackgroundAction(
            action = { arRecorder.pauseRecording() },
            errorCode = "PAUSE_RECORDING_ERROR",
            errorMessage = "Failed to pause recording",
            result = result
        )
    }

    private fun handleResumeRecording(result: MethodChannel.Result) {
        runBackgroundAction(
            action = { arRecorder.resumeRecording() },
            errorCode = "RESUME_RECORDING_ERROR",
            errorMessage = "Failed to resume recording",
            result = result
        )
    }

    private fun handleCancelRecording(result: MethodChannel.Result) {
        runBackgroundAction(
            action = { arRecorder.cancelRecording() },
            errorCode = "CANCEL_RECORDING_ERROR",
            errorMessage = "Failed to cancel recording",
            result = result
        )
    }

    /**
     * Handles stopRecording method call.
     */
    private fun handleStopRecording(result: MethodChannel.Result) {
        runBackgroundAction(
            action = { arRecorder.stopRecording() },
            errorCode = "STOP_RECORDING_ERROR",
            errorMessage = "Failed to stop recording",
            result = result
        )
    }

    private fun runBackgroundAction(
        action: () -> Map<String, Any?>,
        errorCode: String,
        errorMessage: String,
        result: MethodChannel.Result
    ) {
        controlExecutor.execute {
            try {
                val response = action()
                mainHandler.post {
                    result.success(response)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                mainHandler.post {
                    result.error(
                        errorCode,
                        e.message ?: errorMessage,
                        null
                    )
                }
            }
        }
    }

    /**
     * Handles getRecordingState method call.
     */
    private fun handleGetRecordingState(result: MethodChannel.Result) {
        try {
            val response = arRecorder.getRecordingState()
            result.success(response)
        } catch (e: Exception) {
            e.printStackTrace()
            result.error(
                "STATE_ERROR",
                e.message ?: "Failed to get recording state",
                null
            )
        }
    }

    /**
     * Handles checkArAvailability method call.
     * Safe to call on main thread — uses the synchronous cached check.
     */
    private fun handleCheckArAvailability(result: MethodChannel.Result) {
        try {
            val response = arRecorder.checkArAvailability()
            result.success(response)
        } catch (e: Exception) {
            e.printStackTrace()
            result.error(
                "AR_AVAILABILITY_ERROR",
                e.message ?: "Failed to check AR availability",
                null
            )
        }
    }

    /**
     * Handles disposeSession method call.
     * Must run on main thread because textureRegistry.release() requires UI thread.
     */
    private fun handleDisposeSession(result: MethodChannel.Result) {
        try {
            arRecorder.disposeSession()
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            e.printStackTrace()
            result.error(
                "DISPOSE_ERROR",
                e.message ?: "Failed to dispose session",
                null
            )
        }
    }

    /**
     * Releases native resources when the hosting activity is torn down.
     * Safe to call multiple times.
     */
    fun dispose() {
        try {
            arRecorder.disposeSession()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            controlExecutor.shutdown()
        }
    }
}
