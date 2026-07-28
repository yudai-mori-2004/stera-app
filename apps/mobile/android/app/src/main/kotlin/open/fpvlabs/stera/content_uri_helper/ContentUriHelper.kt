package open.fpvlabs.stera.content_uri_helper

/**
 * Interface for Android Content URI operations.
 * Use with jnigen to generate Dart bindings.
 */
interface ContentUriHelper {

    /**
     * Takes persistent read permission for a content URI.
     * @param uriString The content URI string
     * @return true if permission was successfully taken
     */
    fun takePersistentPermission(uriString: String): Boolean

    /**
     * Releases persistent permission for a content URI.
     * @param uriString The content URI string
     * @return true if permission was successfully released
     */
    fun releasePersistentPermission(uriString: String): Boolean

    /**
     * Checks if app has persistent read permission for a URI.
     * @param uriString The content URI string
     * @return true if permission exists
     */
    fun hasPermission(uriString: String): Boolean

    /**
     * Gets the file size for a content URI.
     * @param uriString The content URI string
     * @return File size in bytes, or null if unavailable
     */
    fun getFileSize(uriString: String): Long?

    /**
     * Gets file metadata (name, size, mimeType).
     * @param uriString The content URI string
     * @return Map containing metadata
     */
    fun getFileMetadata(uriString: String): Map<String, Any?>

    /**
     * Reads a chunk of bytes from a file.
     * @param uriString The content URI string
     * @param offset Starting position in bytes
     * @param length Number of bytes to read
     * @return Byte array of the chunk, or null on error
     */
    fun readChunk(uriString: String, offset: Long, length: Int): ByteArray?
}
