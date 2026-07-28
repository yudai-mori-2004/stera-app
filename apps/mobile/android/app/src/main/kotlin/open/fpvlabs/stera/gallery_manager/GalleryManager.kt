package open.fpvlabs.stera.gallery_manager

/**
 * Interface for saving media files to the device gallery.
 */
interface GalleryManager {

    /**
     * Saves a video file to the device gallery.
     * @param sourcePath Path to the source video file
     * @param albumName Album/folder name (default: "FPV")
     * @return true if saved successfully
     */
    fun saveVideoToGallery(sourcePath: String, albumName: String = "FPV"): Boolean

}