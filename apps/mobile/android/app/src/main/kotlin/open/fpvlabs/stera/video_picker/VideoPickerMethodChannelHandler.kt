package open.fpvlabs.stera.video_picker

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Handles Flutter MethodChannel calls for VideoPicker operations.
 */
class VideoPickerMethodChannelHandler(
    activity: Activity,
    binaryMessenger: BinaryMessenger
) {
    companion object {
        private const val CHANNEL_NAME = "custom_document_picker"
    }

    private val videoPicker: VideoPicker = VideoPickerImpl(activity)
    private val methodChannel: MethodChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)
    private var pendingResult: MethodChannel.Result? = null

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickVideos" -> handlePickVideos(result)
                "pickSingleVideo" -> handlePickSingleVideo(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handlePickVideos(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("ALREADY_ACTIVE", "A picker is already active", null)
            return
        }
        pendingResult = result
        videoPicker.pickVideos()
    }

    private fun handlePickSingleVideo(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("ALREADY_ACTIVE", "A picker is already active", null)
            return
        }
        pendingResult = result
        videoPicker.pickSingleVideo()
    }

    /**
     * Must be called from Activity.onActivityResult to handle picker results.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val (handled, result) = videoPicker.handleActivityResult(requestCode, resultCode, data)
        if (handled) {
            pendingResult?.success(result)
            pendingResult = null
        }
    }
}
