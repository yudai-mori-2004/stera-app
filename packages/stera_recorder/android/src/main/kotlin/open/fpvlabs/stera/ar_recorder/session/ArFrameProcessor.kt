package open.fpvlabs.stera.ar_recorder.session

import com.google.ar.core.Camera
import com.google.ar.core.Frame

data class PointCloudFrameData(
    val bytes: ByteArray,
    val validSize: Int,
    val pointCount: Int,
    val release: () -> Unit
)

data class DepthFrameData(
    val bytes: ByteArray,
    val validSize: Int,
    val width: Int,
    val height: Int,
    val bytesPerPixel: Int,
    val pixelStride: Int,
    val rowStride: Int,
    val endianness: String = "little",
    val format: String = "uint16",
    val unit: String = "millimeters",
    val release: () -> Unit
)

interface ArFrameProcessor {
    fun resetAllocationCounters()
    fun prepareForRecording(
        pointCloudPoolCapacity: Int = 20,
        depthPoolCapacity: Int = 24,
        pointCloudBufferSize: Int = 1 * 1024 * 1024,
        depthBufferSize: Int = 4 * 1024 * 1024
    )
    fun getPointCloudBufferAllocations(): Int
    fun getDepthBufferAllocations(): Int
    fun getPointCloudPoolMisses(): Int
    fun getDepthPoolMisses(): Int
    fun getPointCloudPoolStarvationEvents(): Int
    fun getDepthPoolStarvationEvents(): Int
    fun getPointCloudPoolMinAvailable(): Int
    fun getDepthPoolMinAvailable(): Int
    fun getPointCloudPoolMaxInUse(): Int
    fun getDepthPoolMaxInUse(): Int
    fun getPointCloudPoolCapacity(): Int
    fun getDepthPoolCapacity(): Int
    fun getPointCloudPoolAvailableCount(): Int
    fun getPointCloudAcquireCount(): Int
    fun getPointCloudReleaseCount(): Int
    fun getDepthImageAcquireCount(): Int
    fun getDepthImageCloseCount(): Int
    fun extractPose(camera: Camera): FloatArray
    fun extractTrackingState(camera: Camera): String
    fun extractPointCloudFrame(frame: Frame, timestampNs: Long): PointCloudFrameData?
    fun extractDepthImage(frame: Frame): DepthFrameData?
    fun extractIntrinsics(camera: Camera): Map<String, Any>
    fun extractDepthIntrinsics(camera: Camera, depthWidth: Int, depthHeight: Int): Map<String, Any>?
    fun createIntrinsicsJson(intrinsics: Map<String, Any>): String
}
