package io.rootlens.app.video_metadata_extractor

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Implementation of VideoMetadataExtractor for video operations.
 */
class VideoMetadataExtractorImpl(private val context: Context) : VideoMetadataExtractor {

    override fun extractThumbnail(uriString: String, timeMs: Long): String? {
        return try {
            val retriever = MediaMetadataRetriever()

            try {
                // Handle both content:// URIs and file paths
                if (uriString.startsWith("content://")) {
                    val uri = Uri.parse(uriString)
                    retriever.setDataSource(context, uri)
                } else if (uriString.startsWith("file://")) {
                    val filePath = uriString.removePrefix("file://")
                    retriever.setDataSource(filePath)
                } else {
                    // Assume it's a direct file path
                    retriever.setDataSource(uriString)
                }

                // Extract frame at specified time (in microseconds)
                val bitmap = retriever.getFrameAtTime(
                    timeMs * 1000, // Convert milliseconds to microseconds
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                )

                if (bitmap == null) {
                    return null
                }

                // Create thumbnails directory in internal storage
                val thumbnailsDir = File(context.filesDir, "thumbnails")
                if (!thumbnailsDir.exists()) {
                    thumbnailsDir.mkdirs()
                }

                // Generate unique filename based on URI/path hash
                val fileName = "${uriString.hashCode()}.jpg"
                val thumbnailFile = File(thumbnailsDir, fileName)

                // Save bitmap as JPEG
                FileOutputStream(thumbnailFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }

                bitmap.recycle()

                println("✅ Thumbnail extracted: ${thumbnailFile.absolutePath}")
                return thumbnailFile.absolutePath

            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    override fun getVideoDuration(uriString: String): Int? {
        return try {
            val retriever = MediaMetadataRetriever()

            try {
                // Handle both content:// URIs and file paths
                if (uriString.startsWith("content://")) {
                    val uri = Uri.parse(uriString)
                    retriever.setDataSource(context, uri)
                } else if (uriString.startsWith("file://")) {
                    val filePath = uriString.removePrefix("file://")
                    retriever.setDataSource(filePath)
                } else {
                    // Assume it's a direct file path
                    retriever.setDataSource(uriString)
                }

                // Get duration in milliseconds
                val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)

                if (durationMs != null) {
                    // Convert to seconds
                    val durationSeconds = (durationMs.toLong() / 1000).toInt()
                    println("✅ Video duration: $durationSeconds seconds")
                    return durationSeconds
                }

                return null
            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    override fun openVideoInViewer(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            
            // For SAF content URIs (from document picker), we need to grant URI permission
            // to the receiving app via the intent
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "video/*")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                
                // Grant read permission to the receiving app
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            // For SAF URIs, we need to grant permission to all potential handlers
            // Use a chooser to let the user pick an app
            val chooserIntent = Intent.createChooser(intent, "Open video with").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            // Grant URI permission to all potential receivers
            val resInfoList = context.packageManager.queryIntentActivities(intent, 0)
            for (resolveInfo in resInfoList) {
                val packageName = resolveInfo.activityInfo.packageName
                context.grantUriPermission(
                    packageName,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }

            context.startActivity(chooserIntent)
            println("✅ Opened video chooser for: $uriString")
            true
        } catch (e: SecurityException) {
            // If we can't grant permission (e.g., the URI is from SAF without persistent permission),
            // try to open using an intent that doesn't require forwarding the URI permission
            println("⚠️ SecurityException, trying alternative approach: ${e.message}")
            try {
                // Try opening with just the URI - some apps may be able to handle it
                val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse(uriString)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                context.startActivity(Intent.createChooser(fallbackIntent, "Open video with").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                true
            } catch (e2: Exception) {
                println("❌ Failed to open video: ${e2.message}")
                e2.printStackTrace()
                false
            }
        } catch (e: Exception) {
            println("❌ Failed to open video: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    override fun saveVideoToGallery(sourcePath: String): Boolean {
        return try {
            val videoFile = File(sourcePath)

            if (!videoFile.exists()) {
                println("❌ Source video file does not exist: $sourcePath")
                return false
            }

            // For Android 10+ (API 29+), use MediaStore
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, videoFile.name)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/FPV")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }

                val uri = context.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)

                if (uri != null) {
                    context.contentResolver.openOutputStream(uri)?.use { output ->
                        FileInputStream(videoFile).use { input ->
                            input.copyTo(output)
                        }
                    }

                    // Mark as not pending anymore
                    values.clear()
                    values.put(MediaStore.Video.Media.IS_PENDING, 0)
                    context.contentResolver.update(uri, values, null, null)

                    println("✅ Video saved to gallery using MediaStore: ${videoFile.name}")
                    true
                } else {
                    println("❌ Failed to create MediaStore entry")
                    false
                }
            } else {
                // For Android 9 and below, use legacy approach with WRITE_EXTERNAL_STORAGE
                val moviesDir = File(
                    android.os.Environment.getExternalStoragePublicDirectory(
                        android.os.Environment.DIRECTORY_MOVIES
                    ), "FPV"
                )

                if (!moviesDir.exists()) {
                    moviesDir.mkdirs()
                }

                val destFile = File(moviesDir, videoFile.name)
                FileInputStream(videoFile).use { input ->
                    FileOutputStream(destFile).use { output ->
                        input.copyTo(output)
                    }
                }

                // Notify MediaScanner to index the file
                val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                mediaScanIntent.data = Uri.fromFile(destFile)
                context.sendBroadcast(mediaScanIntent)

                println("✅ Video saved to gallery using legacy approach: ${videoFile.name}")
                true
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("❌ Error saving video to gallery: ${e.message}")
            false
        }
    }
}
