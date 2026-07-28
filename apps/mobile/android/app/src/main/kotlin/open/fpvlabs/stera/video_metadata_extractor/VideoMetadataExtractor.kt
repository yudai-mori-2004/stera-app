package open.fpvlabs.stera.video_metadata_extractor

/**
 * Interface for extracting metadata and thumbnails from video files.
 */
interface VideoMetadataExtractor {

    /**
     * Extracts a thumbnail frame from a video.
     * @param uriString Video URI or file path
     * @param timeMs Time position in milliseconds
     * @return Path to saved thumbnail JPEG, or null on error
     */
    fun extractThumbnail(uriString: String, timeMs: Long): String?

    /**
     * Gets the duration of a video.
     * @param uriString Video URI or file path
     * @return Duration in seconds, or null on error
     */
    fun getVideoDuration(uriString: String): Int?

    /**
     * Opens a video in the system's default viewer.
     * @param uriString Video URI
     * @return true if video was opened successfully
     */
    fun openVideoInViewer(uriString: String): Boolean

    /**
     * Saves a video to the device gallery.
     * @param sourcePath Path to the source video file
     * @return true if video was saved successfully
     */
    fun saveVideoToGallery(sourcePath: String): Boolean
}