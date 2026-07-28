package open.fpvlabs.stera.gallery_manager

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Implementation of GalleryManager for saving media to device gallery.
 */
class GalleryManagerImpl(private val context: Context) : GalleryManager {

    override fun saveVideoToGallery(sourcePath: String, albumName: String): Boolean {
        return try {
            val videoFile = File(sourcePath)

            if (!videoFile.exists()) {
                println("❌ Source video file does not exist: $sourcePath")
                return false
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveVideoUsingMediaStore(videoFile, albumName)
            } else {
                saveVideoUsingLegacyApproach(videoFile, albumName)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            println("❌ Error saving video to gallery: ${e.message}")
            false
        }
    }

    private fun saveVideoUsingMediaStore(videoFile: File, albumName: String): Boolean {
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, videoFile.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/$albumName")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }

        val uri = context.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)

        return if (uri != null) {
            context.contentResolver.openOutputStream(uri)?.use { output ->
                FileInputStream(videoFile).use { input ->
                    input.copyTo(output)
                }
            }

            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            context.contentResolver.update(uri, values, null, null)

            println("✅ Video saved to gallery using MediaStore: ${videoFile.name}")
            true
        } else {
            println("❌ Failed to create MediaStore entry")
            false
        }
    }

    private fun saveVideoUsingLegacyApproach(videoFile: File, albumName: String): Boolean {
        val moviesDir = File(
            android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_MOVIES
            ), albumName
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
        return true
    }

    private fun saveImageUsingMediaStore(imageFile: File, albumName: String): Boolean {
        val mimeType = when {
            imageFile.name.endsWith(".png", ignoreCase = true) -> "image/png"
            imageFile.name.endsWith(".gif", ignoreCase = true) -> "image/gif"
            imageFile.name.endsWith(".webp", ignoreCase = true) -> "image/webp"
            else -> "image/jpeg"
        }

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, imageFile.name)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$albumName")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }

        val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)

        return if (uri != null) {
            context.contentResolver.openOutputStream(uri)?.use { output ->
                FileInputStream(imageFile).use { input ->
                    input.copyTo(output)
                }
            }

            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            context.contentResolver.update(uri, values, null, null)

            println("✅ Image saved to gallery using MediaStore: ${imageFile.name}")
            true
        } else {
            println("❌ Failed to create MediaStore entry for image")
            false
        }
    }

    private fun saveImageUsingLegacyApproach(imageFile: File, albumName: String): Boolean {
        val picturesDir = File(
            android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_PICTURES
            ), albumName
        )

        if (!picturesDir.exists()) {
            picturesDir.mkdirs()
        }

        val destFile = File(picturesDir, imageFile.name)
        FileInputStream(imageFile).use { input ->
            FileOutputStream(destFile).use { output ->
                input.copyTo(output)
            }
        }

        // Notify MediaScanner to index the file
        val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
        mediaScanIntent.data = Uri.fromFile(destFile)
        context.sendBroadcast(mediaScanIntent)

        println("✅ Image saved to gallery using legacy approach: ${imageFile.name}")
        return true
    }
}
