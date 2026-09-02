package io.rootlens.app.gallery_manager

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Handles Flutter MethodChannel calls for GalleryManager operations.
 */
class GalleryManagerMethodChannelHandler(
    context: Context,
    binaryMessenger: BinaryMessenger
) {
    companion object {
        private const val CHANNEL_NAME = "gallery_manager"
    }

    private val galleryManager: GalleryManager = GalleryManagerImpl(context)
    private val methodChannel: MethodChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveVideoToGallery" -> handleSaveVideoToGallery(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleSaveVideoToGallery(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val albumName = call.argument<String>("albumName") ?: "FPV"

        if (sourcePath != null) {
            val success = galleryManager.saveVideoToGallery(sourcePath, albumName)
            result.success(success)
        } else {
            result.error("INVALID_ARGUMENT", "Source path is null", null)
        }
    }

}
