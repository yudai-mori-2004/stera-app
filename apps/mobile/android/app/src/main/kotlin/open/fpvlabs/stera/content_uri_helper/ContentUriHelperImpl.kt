package open.fpvlabs.stera.content_uri_helper

import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import java.io.InputStream

/**
 * Implementation of ContentUriHelper for Android Content URI operations.
 */
class ContentUriHelperImpl(private val context: Context) : ContentUriHelper {

    override fun takePersistentPermission(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            context.contentResolver.takePersistableUriPermission(uri, flags)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    override fun releasePersistentPermission(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            context.contentResolver.releasePersistableUriPermission(uri, flags)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    override fun hasPermission(uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            val persistedUris = context.contentResolver.persistedUriPermissions
            persistedUris.any { it.uri == uri && it.isReadPermission }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    override fun getFileSize(uriString: String): Long? {
        return try {
            val uri = Uri.parse(uriString)
            val cursor: Cursor? = context.contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex != -1) {
                        return it.getLong(sizeIndex)
                    }
                }
            }
            null
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override fun getFileMetadata(uriString: String): Map<String, Any?> {
        val metadata = mutableMapOf<String, Any?>()

        try {
            val uri = Uri.parse(uriString)
            val cursor: Cursor? = context.contentResolver.query(uri, null, null, null, null)

            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)

                    if (nameIndex != -1) {
                        metadata["name"] = it.getString(nameIndex)
                    }

                    if (sizeIndex != -1) {
                        metadata["size"] = it.getLong(sizeIndex)
                    }

                    metadata["mimeType"] = context.contentResolver.getType(uri)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return metadata
    }

    override fun readChunk(uriString: String, offset: Long, length: Int): ByteArray? {
        return try {
            val uri = Uri.parse(uriString)
            val inputStream: InputStream? = context.contentResolver.openInputStream(uri)

            inputStream?.use { stream ->
                // Skip to offset
                var skipped = 0L
                while (skipped < offset) {
                    val toSkip = offset - skipped
                    val actuallySkipped = stream.skip(toSkip)
                    if (actuallySkipped <= 0) break
                    skipped += actuallySkipped
                }

                // Read chunk
                val buffer = ByteArray(length)
                var totalRead = 0

                while (totalRead < length) {
                    val read = stream.read(buffer, totalRead, length - totalRead)
                    if (read == -1) break
                    totalRead += read
                }

                // Return exact bytes read (might be less than requested at end of file)
                if (totalRead < length) {
                    buffer.copyOf(totalRead)
                } else {
                    buffer
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
