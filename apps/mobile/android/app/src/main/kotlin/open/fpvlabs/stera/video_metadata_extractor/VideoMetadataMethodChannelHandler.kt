package open.fpvlabs.stera.video_metadata_extractor

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Handles Flutter MethodChannel calls for VideoMetadataExtractor operations.
 */
class VideoMetadataMethodChannelHandler(
    context: Context,
    binaryMessenger: BinaryMessenger
) {
    companion object {
        private const val CHANNEL_NAME = "video_helper"
    }

    private val videoMetadataExtractor: VideoMetadataExtractor = VideoMetadataExtractorImpl(context)
    private val methodChannel: MethodChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "extractThumbnail" -> handleExtractThumbnail(call, result)
                "getVideoDuration" -> handleGetVideoDuration(call, result)
                "openVideoInViewer" -> handleOpenVideoInViewer(call, result)
                "saveVideoToGallery" -> handleSaveVideoToGallery(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleExtractThumbnail(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val timeMs = call.argument<Number>("timeMs") ?: 0

        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "URI is null", null)
            return
        }

        // Run on background thread to avoid blocking Android main thread
        // Flutter side also uses isolate for double protection
        Thread {
            try {
                val thumbnailPath = videoMetadataExtractor.extractThumbnail(uriString, timeMs.toLong())
                result.success(thumbnailPath)
            } catch (e: Exception) {
                result.error("EXTRACTION_ERROR", e.message, null)
            }
        }.start()
    }

    private fun handleGetVideoDuration(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")

        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "URI is null", null)
            return
        }

        // Run on background thread to avoid blocking Android main thread
        // Flutter side also uses isolate for double protection
        Thread {
            try {
                val durationSeconds = videoMetadataExtractor.getVideoDuration(uriString)
                result.success(durationSeconds)
            } catch (e: Exception) {
                result.error("DURATION_ERROR", e.message, null)
            }
        }.start()
    }

    private fun handleOpenVideoInViewer(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")

        if (uriString != null) {
            val success = videoMetadataExtractor.openVideoInViewer(uriString)
            result.success(success)
        } else {
            result.error("INVALID_ARGUMENT", "URI is null", null)
        }
    }

    private fun handleSaveVideoToGallery(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")

        if (sourcePath != null) {
            val success = videoMetadataExtractor.saveVideoToGallery(sourcePath)
            result.success(success)
        } else {
            result.error("INVALID_ARGUMENT", "Source path is null", null)
        }
    }
}
