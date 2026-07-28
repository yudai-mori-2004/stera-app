package open.fpvlabs.stera.video_picker

import android.content.Intent

/**
 * Interface for video picker operations.
 */
interface VideoPicker {

    /**
     * Opens the system file picker for multiple video selection.
     * Results are returned via the callback set in the handler.
     */
    fun pickVideos()

    /**
     * Opens the system file picker for single video selection.
     * Results are returned via the callback set in the handler.
     */
    fun pickSingleVideo()

    /**
     * Handles the activity result from the picker.
     * @param requestCode The request code from onActivityResult
     * @param resultCode The result code from onActivityResult
     * @param data The intent data from onActivityResult
     * @return Pair of (isHandled, result) - result is List<String>? for multiple, String? for single
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Pair<Boolean, Any?>
}