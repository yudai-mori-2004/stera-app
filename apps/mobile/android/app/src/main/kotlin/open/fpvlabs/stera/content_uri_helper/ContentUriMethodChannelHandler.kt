package open.fpvlabs.stera.content_uri_helper

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Handles Flutter MethodChannel calls for ContentUriHelper operations.
 */
class ContentUriMethodChannelHandler(
    context: Context,
    binaryMessenger: BinaryMessenger
) {
    companion object {
        private const val CHANNEL_NAME = "content_uri_helper"
    }

    private val contentUriHelper: ContentUriHelper = ContentUriHelperImpl(context)
    private val methodChannel: MethodChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePersistentPermission" -> handleTakePersistentPermission(call, result)
                "getFileSize" -> handleGetFileSize(call, result)
                "getFileMetadata" -> handleGetFileMetadata(call, result)
                "readChunk" -> handleReadChunk(call, result)
                "releasePersistentPermission" -> handleReleasePersistentPermission(call, result)
                "hasPermission" -> handleHasPermission(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleTakePersistentPermission(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString != null) {
            val success = contentUriHelper.takePersistentPermission(uriString)
            result.success(success)
        } else {
            result.error("INVALID_ARGUMENT", "URI is null", null)
        }
    }

    private fun handleGetFileSize(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString != null) {
            val size = contentUriHelper.getFileSize(uriString)
            result.success(size)
        } else {
            result.error("INVALID_ARGUMENT", "URI is null", null)
        }
    }

    private fun handleGetFileMetadata(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString != null) {
            val metadata = contentUriHelper.getFileMetadata(uriString)
            result.success(metadata)
        } else {
            result.error("INVALID_ARGUMENT", "URI is null", null)
        }
    }

    private fun handleReadChunk(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        // Handle both Int and Long from Dart by accepting as Number
        val offsetNumber = call.argument<Number>("offset")
        val lengthNumber = call.argument<Number>("length")

        if (uriString != null && offsetNumber != null && lengthNumber != null) {
            val offset = offsetNumber.toLong()
            val length = lengthNumber.toInt()
            val chunk = contentUriHelper.readChunk(uriString, offset, length)
            result.success(chunk)
        } else {
            result.error("INVALID_ARGUMENT", "Invalid arguments", null)
        }
    }

    private fun handleReleasePersistentPermission(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString != null) {
            val success = contentUriHelper.releasePersistentPermission(uriString)
            result.success(success)
        } else {
            result.error("INVALID_ARGUMENT", "URI is null", null)
        }
    }

    private fun handleHasPermission(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString != null) {
            val hasPermission = contentUriHelper.hasPermission(uriString)
            result.success(hasPermission)
        } else {
            result.error("INVALID_ARGUMENT", "URI is null", null)
        }
    }
}
