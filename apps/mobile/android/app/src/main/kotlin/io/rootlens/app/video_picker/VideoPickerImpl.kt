package io.rootlens.app.video_picker

import android.app.Activity
import android.content.Intent

/**
 * Implementation of VideoPicker for video selection operations.
 */
class VideoPickerImpl(private val activity: Activity) : VideoPicker {

    companion object {
        const val REQUEST_CODE_PICK_VIDEOS = 1001
        const val REQUEST_CODE_PICK_SINGLE_VIDEO = 1002
    }

    override fun pickVideos() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_CODE_PICK_VIDEOS)
    }

    override fun pickSingleVideo() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_CODE_PICK_SINGLE_VIDEO)
    }

    override fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Pair<Boolean, Any?> {
        return when (requestCode) {
            REQUEST_CODE_PICK_VIDEOS -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val uris = mutableListOf<String>()

                    // Handle multiple files
                    data.clipData?.let { clipData ->
                        for (i in 0 until clipData.itemCount) {
                            val uri = clipData.getItemAt(i).uri
                            uris.add(uri.toString())
                        }
                    }

                    // Handle single file (when multiple selection but only one file selected)
                    if (uris.isEmpty() && data.data != null) {
                        uris.add(data.data.toString())
                    }

                    Pair(true, uris)
                } else {
                    Pair(true, null)
                }
            }
            REQUEST_CODE_PICK_SINGLE_VIDEO -> {
                if (resultCode == Activity.RESULT_OK && data?.data != null) {
                    Pair(true, data.data.toString())
                } else {
                    Pair(true, null)
                }
            }
            else -> Pair(false, null)
        }
    }
}
