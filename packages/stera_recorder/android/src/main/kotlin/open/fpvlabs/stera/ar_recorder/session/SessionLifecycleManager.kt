package open.fpvlabs.stera.ar_recorder.session

import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.HandlerThread
import io.flutter.view.TextureRegistry

class SessionLifecycleManager {
    data class ResolutionPolicyResult(
        val configuredVideoWidth: Int,
        val configuredVideoHeight: Int,
        val previewWidth: Int,
        val previewHeight: Int,
        val cameraResolution: String,
        val recordingResolution: String,
        val isLowQualityMode: Boolean,
        val lowQualityReason: String?,
        val previewResolutionDerived: Boolean
    )

    data class ThreadHandles(
        val frameThread: HandlerThread,
        val frameHandler: Handler,
        val writerThread: HandlerThread,
        val writerHandler: Handler
    )

    fun applyResolutionPolicyFromCameraConfig(
        sensorWidth: Int,
        sensorHeight: Int,
        videoWidth: Int,
        videoHeight: Int
    ): ResolutionPolicyResult {
        val sourceLandscapeWidth = maxOf(sensorWidth, sensorHeight)
        val sourceLandscapeHeight = minOf(sensorWidth, sensorHeight)
        val targetLandscapeWidth = maxOf(videoWidth, videoHeight)
        val targetLandscapeHeight = minOf(videoWidth, videoHeight)
        val canUseTargetResolution =
            sourceLandscapeWidth >= targetLandscapeWidth &&
                sourceLandscapeHeight >= targetLandscapeHeight
        val configuredWidth: Int
        val configuredHeight: Int
        val isLowQuality: Boolean
        val lowQualityReason: String?
        if (canUseTargetResolution) {
            configuredWidth = targetLandscapeWidth
            configuredHeight = targetLandscapeHeight
            isLowQuality = false
            lowQualityReason = null
        } else {
            configuredWidth = (sourceLandscapeWidth / 16) * 16
            configuredHeight = (sourceLandscapeHeight / 16) * 16
            isLowQuality = true
            lowQualityReason = "camera_resolution_below_target"
        }
        return ResolutionPolicyResult(
            configuredVideoWidth = configuredWidth,
            configuredVideoHeight = configuredHeight,
            previewWidth = configuredWidth,
            previewHeight = configuredHeight,
            cameraResolution = "${sourceLandscapeWidth}x${sourceLandscapeHeight}",
            recordingResolution = "${configuredWidth}x${configuredHeight}",
            isLowQualityMode = isLowQuality,
            lowQualityReason = lowQualityReason,
            previewResolutionDerived = true
        )
    }

    fun startThreads(runFrameLoop: () -> Unit): ThreadHandles {
        val frameThread = HandlerThread("ArFrameThread").apply { start() }
        val frameHandler = Handler(frameThread.looper)
        val writerThread = HandlerThread("ArWriterThread").apply { start() }
        val writerHandler = Handler(writerThread.looper)
        frameHandler.post { runFrameLoop() }
        return ThreadHandles(frameThread, frameHandler, writerThread, writerHandler)
    }

    fun releaseFlutterPreviewTexture(
        flutterTexture: TextureRegistry.SurfaceTextureEntry?,
        onRelease: (SurfaceTexture?) -> Unit
    ) {
        flutterTexture?.release()
        onRelease(null)
    }

    fun stopThreads(frameThread: HandlerThread?, writerThread: HandlerThread?) {
        frameThread?.quitSafely()
        writerThread?.quitSafely()
        try {
            frameThread?.join()
            writerThread?.join()
        } catch (_: InterruptedException) {
        }
    }
}
