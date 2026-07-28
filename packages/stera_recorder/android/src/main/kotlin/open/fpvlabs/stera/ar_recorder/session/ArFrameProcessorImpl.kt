package open.fpvlabs.stera.ar_recorder.session

import android.media.Image
import open.fpvlabs.stera.ar_recorder.ArTrackingState
import com.google.ar.core.Camera
import com.google.ar.core.Frame
import com.google.ar.core.PointCloud
import com.google.ar.core.TrackingState
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Extracts pose, point cloud, depth, and intrinsics from ARCore frames.
 */
class ArFrameProcessorImpl : ArFrameProcessor {

    private companion object {
        private const val DEFAULT_POINTCLOUD_POOL_CAPACITY = 20
        private const val DEFAULT_DEPTH_POOL_CAPACITY = 24
        private const val DEFAULT_POINTCLOUD_BUFFER_SIZE = 1 * 1024 * 1024
        private const val DEFAULT_DEPTH_BUFFER_SIZE = 4 * 1024 * 1024
    }

    private val pointCloudPool = ArrayDeque<ByteArray>()
    private val depthPool = ArrayDeque<ByteArray>()
    private var pointCloudPoolBufferSize: Int = DEFAULT_POINTCLOUD_BUFFER_SIZE
    private var depthPoolBufferSize: Int = DEFAULT_DEPTH_BUFFER_SIZE
    private var pointCloudBufferAllocations: Int = 0
    private var depthBufferAllocations: Int = 0
    private var pointCloudPoolMisses: Int = 0
    private var depthPoolMisses: Int = 0
    private var pointCloudPoolStarvationEvents: Int = 0
    private var depthPoolStarvationEvents: Int = 0
    private var pointCloudPoolMinAvailable: Int = Int.MAX_VALUE
    private var depthPoolMinAvailable: Int = Int.MAX_VALUE
    private var pointCloudPoolMaxInUse: Int = 0
    private var depthPoolMaxInUse: Int = 0
    private var pointCloudAcquireCount: Int = 0
    private var pointCloudReleaseCount: Int = 0
    private var depthImageAcquireCount: Int = 0
    private var depthImageCloseCount: Int = 0
    private var pointCloudPoolCapacity: Int = DEFAULT_POINTCLOUD_POOL_CAPACITY
    private var depthPoolCapacity: Int = DEFAULT_DEPTH_POOL_CAPACITY

    init {
        prepareForRecording(
            pointCloudPoolCapacity = DEFAULT_POINTCLOUD_POOL_CAPACITY,
            depthPoolCapacity = DEFAULT_DEPTH_POOL_CAPACITY,
            pointCloudBufferSize = DEFAULT_POINTCLOUD_BUFFER_SIZE,
            depthBufferSize = DEFAULT_DEPTH_BUFFER_SIZE
        )
    }

    override fun resetAllocationCounters() {
        pointCloudBufferAllocations = 0
        depthBufferAllocations = 0
        pointCloudPoolMisses = 0
        depthPoolMisses = 0
        pointCloudPoolStarvationEvents = 0
        depthPoolStarvationEvents = 0
        pointCloudPoolMinAvailable = Int.MAX_VALUE
        depthPoolMinAvailable = Int.MAX_VALUE
        pointCloudPoolMaxInUse = 0
        depthPoolMaxInUse = 0
        pointCloudAcquireCount = 0
        pointCloudReleaseCount = 0
        depthImageAcquireCount = 0
        depthImageCloseCount = 0
    }

    override fun prepareForRecording(
        pointCloudPoolCapacity: Int,
        depthPoolCapacity: Int,
        pointCloudBufferSize: Int,
        depthBufferSize: Int
    ) {
        resetAllocationCounters()
        val pcCapacity = pointCloudPoolCapacity.coerceAtLeast(1)
        val dCapacity = depthPoolCapacity.coerceAtLeast(1)
        this.pointCloudPoolCapacity = pcCapacity
        this.depthPoolCapacity = dCapacity
        pointCloudPoolBufferSize = pointCloudBufferSize
        depthPoolBufferSize = depthBufferSize
        synchronized(pointCloudPool) {
            pointCloudPool.clear()
            repeat(pcCapacity) {
                pointCloudPool.addLast(ByteArray(pointCloudPoolBufferSize))
            }
            pointCloudPoolMinAvailable = pointCloudPool.size
        }
        synchronized(depthPool) {
            depthPool.clear()
            repeat(dCapacity) {
                depthPool.addLast(ByteArray(depthPoolBufferSize))
            }
            depthPoolMinAvailable = depthPool.size
        }
    }

    override fun getPointCloudBufferAllocations(): Int = pointCloudBufferAllocations

    override fun getDepthBufferAllocations(): Int = depthBufferAllocations

    override fun getPointCloudPoolMisses(): Int = pointCloudPoolMisses

    override fun getDepthPoolMisses(): Int = depthPoolMisses

    override fun getPointCloudPoolStarvationEvents(): Int = pointCloudPoolStarvationEvents

    override fun getDepthPoolStarvationEvents(): Int = depthPoolStarvationEvents

    override fun getPointCloudPoolMinAvailable(): Int = if (pointCloudPoolMinAvailable == Int.MAX_VALUE) 0 else pointCloudPoolMinAvailable

    override fun getDepthPoolMinAvailable(): Int = if (depthPoolMinAvailable == Int.MAX_VALUE) 0 else depthPoolMinAvailable

    override fun getPointCloudPoolMaxInUse(): Int = pointCloudPoolMaxInUse

    override fun getDepthPoolMaxInUse(): Int = depthPoolMaxInUse

    override fun getPointCloudPoolCapacity(): Int = pointCloudPoolCapacity

    override fun getDepthPoolCapacity(): Int = depthPoolCapacity

    override fun getPointCloudPoolAvailableCount(): Int = synchronized(pointCloudPool) { pointCloudPool.size }

    override fun getPointCloudAcquireCount(): Int = pointCloudAcquireCount

    override fun getPointCloudReleaseCount(): Int = pointCloudReleaseCount

    override fun getDepthImageAcquireCount(): Int = depthImageAcquireCount

    override fun getDepthImageCloseCount(): Int = depthImageCloseCount

    /**
     * Extracts camera pose as a FloatArray.
     * Format: [tx, ty, tz, qx, qy, qz, qw]
     * Note: Timestamp is handled separately to preserve precision.
     */
    override fun extractPose(camera: Camera): FloatArray {
        val pose = camera.pose

        val translation = pose.translation
        val quaternion = pose.rotationQuaternion

        return floatArrayOf(
            translation[0],
            translation[1],
            translation[2],
            quaternion[0],
            quaternion[1],
            quaternion[2],
            quaternion[3]
        )
    }

    /**
     * Extracts tracking state as a string.
     */
    override fun extractTrackingState(camera: Camera): String {
        return ArTrackingState.fromArcoreState(camera.trackingState).name
    }

    /**
     * Extracts point cloud data as a ByteArray.
     * Format: [timestamp_ns: Int64][numPoints: Int32] followed by [x, y, z, confidence: Float32] * N
     * Returns null if point cloud is empty or extraction fails.
     */
    override fun extractPointCloudFrame(frame: Frame, timestampNs: Long): PointCloudFrameData? {
        var pointCloud: PointCloud? = null
        return try {
            pointCloud = frame.acquirePointCloud()
            pointCloudAcquireCount++

            val numPoints = pointCloud.points.remaining() / 4
            if (numPoints == 0) {
                return null
            }

            // Create ByteBuffer for output
            // 8 bytes for timestamp + 4 bytes for count + (4 floats * 4 bytes) per point
            val bufferSize = 8 + 4 + (numPoints * 4 * 4)
            val buffer = acquireBuffer(pointCloudPool, requiredSize = bufferSize, isDepth = false) ?: run {
                pointCloudPoolMisses++
                return null
            }
            var offset = 0

            putLongLE(buffer, offset, timestampNs)
            offset += 8
            putIntLE(buffer, offset, numPoints)
            offset += 4

            // Write points. ARCore packs 4 floats per point ([x, y, z, confidence])
            // in a native little-endian FloatBuffer laid out exactly as our output,
            // so pull all floats out in one bulk read and write them in one bulk put
            // instead of 16 manual byte writes per point.
            val points = pointCloud.points
            val floatCount = numPoints * 4
            val scratch = FloatArray(floatCount)
            points.get(scratch, 0, floatCount)
            ByteBuffer.wrap(buffer, offset, floatCount * 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .asFloatBuffer()
                .put(scratch, 0, floatCount)
            offset += floatCount * 4

            PointCloudFrameData(
                bytes = buffer,
                validSize = bufferSize,
                pointCount = numPoints,
                release = { releaseBuffer(pointCloudPool, buffer) }
            )
        } catch (e: Exception) {
            println("❌ Failed to extract point cloud: ${e.message}")
            e.printStackTrace()
            null
        } finally {
            if (pointCloud != null) {
                pointCloud.release()
                pointCloudReleaseCount++
            }
        }
    }

    /**
     * Extracts depth image as a ByteArray.
     * Returns null if depth is not available or extraction fails.
     */
    override fun extractDepthImage(frame: Frame): DepthFrameData? {
        var depthImage: Image? = null
        return try {
            depthImage = frame.acquireDepthImage()
            depthImageAcquireCount++

            val planes = depthImage.planes
            if (planes.isEmpty()) {
                return null
            }

            val width = depthImage.width
            val height = depthImage.height
            val plane = planes[0]
            val buffer = plane.buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride

            // ARCore depth image uses 16-bit unsigned depth in millimeters.
            val bytesPerPixel = 2
            val expectedBytes = width * height * bytesPerPixel
            val packedDepth = acquireBuffer(depthPool, requiredSize = expectedBytes, isDepth = true) ?: run {
                depthPoolMisses++
                return null
            }

            // Depth16 is tightly-packed little-endian uint16 millimeters and our
            // output uses the same byte layout, so when pixels aren't strided we can
            // bulk-copy whole rows (or the entire image when there's no row padding)
            // instead of two bounds-checked byte reads + writes per pixel.
            val rowBytes = width * bytesPerPixel
            if (pixelStride == bytesPerPixel) {
                if (rowStride == rowBytes) {
                    buffer.position(0)
                    buffer.get(packedDepth, 0, expectedBytes)
                } else {
                    for (y in 0 until height) {
                        buffer.position(y * rowStride)
                        buffer.get(packedDepth, y * rowBytes, rowBytes)
                    }
                }
            } else {
                // Strided pixels (padding between samples): copy pixel by pixel.
                for (y in 0 until height) {
                    val srcRowOffset = y * rowStride
                    val dstRowOffset = y * rowBytes
                    for (x in 0 until width) {
                        val srcPixelOffset = srcRowOffset + (x * pixelStride)
                        val dstOffset = dstRowOffset + (x * bytesPerPixel)
                        packedDepth[dstOffset] = buffer.get(srcPixelOffset)
                        packedDepth[dstOffset + 1] = buffer.get(srcPixelOffset + 1)
                    }
                }
            }

            DepthFrameData(
                bytes = packedDepth,
                validSize = expectedBytes,
                width = width,
                height = height,
                bytesPerPixel = bytesPerPixel,
                pixelStride = pixelStride,
                rowStride = rowStride,
                release = { releaseBuffer(depthPool, packedDepth) }
            )
        } catch (e: Exception) {
            println("❌ Failed to extract depth image: ${e.message}")
            e.printStackTrace()
            null
        } finally {
            if (depthImage != null) {
                depthImage.close()
                depthImageCloseCount++
            }
        }
    }

    /**
     * Extracts depth camera intrinsics by scaling RGB intrinsics to depth resolution.
     */
    override fun extractDepthIntrinsics(camera: Camera, depthWidth: Int, depthHeight: Int): Map<String, Any>? {
        if (depthWidth == 0 || depthHeight == 0) return null

        val rgbIntrinsics = camera.imageIntrinsics
        val rgbW = rgbIntrinsics.imageDimensions[0].toDouble()
        val rgbH = rgbIntrinsics.imageDimensions[1].toDouble()
        if (rgbW == 0.0 || rgbH == 0.0) return null

        val scaleX = depthWidth.toDouble() / rgbW
        val scaleY = depthHeight.toDouble() / rgbH

        return mapOf(
            "focalLengthX" to (rgbIntrinsics.focalLength[0].toDouble() * scaleX),
            "focalLengthY" to (rgbIntrinsics.focalLength[1].toDouble() * scaleY),
            "principalPointX" to (rgbIntrinsics.principalPoint[0].toDouble() * scaleX),
            "principalPointY" to (rgbIntrinsics.principalPoint[1].toDouble() * scaleY),
            "imageWidth" to depthWidth,
            "imageHeight" to depthHeight
        )
    }

    /**
     * Extracts camera intrinsics as a Map.
     */
    override fun extractIntrinsics(camera: Camera): Map<String, Any> {
        val intrinsics = camera.imageIntrinsics

        val focalLength = intrinsics.focalLength
        val principalPoint = intrinsics.principalPoint
        val imageSize = intrinsics.imageDimensions

        return mapOf(
            "focalLengthX" to focalLength[0],
            "focalLengthY" to focalLength[1],
            "principalPointX" to principalPoint[0],
            "principalPointY" to principalPoint[1],
            "imageWidth" to imageSize[0],
            "imageHeight" to imageSize[1]
        )
    }

    /**
     * Creates the intrinsics JSON string for storage.
     */
    override fun createIntrinsicsJson(intrinsics: Map<String, Any>): String {
        val jsonBuilder = StringBuilder()
        jsonBuilder.append("{\n")
        jsonBuilder.append("  \"focalLengthX\": ${intrinsics["focalLengthX"]},\n")
        jsonBuilder.append("  \"focalLengthY\": ${intrinsics["focalLengthY"]},\n")
        jsonBuilder.append("  \"principalPointX\": ${intrinsics["principalPointX"]},\n")
        jsonBuilder.append("  \"principalPointY\": ${intrinsics["principalPointY"]},\n")
        jsonBuilder.append("  \"imageWidth\": ${intrinsics["imageWidth"]},\n")
        jsonBuilder.append("  \"imageHeight\": ${intrinsics["imageHeight"]},\n")
        jsonBuilder.append("  \"distortionCoeffs\": []\n") // ARCore doesn't expose distortion coefficients
        jsonBuilder.append("}")
        return jsonBuilder.toString()
    }

    private fun acquireBuffer(pool: ArrayDeque<ByteArray>, requiredSize: Int, isDepth: Boolean): ByteArray? {
        synchronized(pool) {
            val availableBefore = pool.size
            if (pool === pointCloudPool && availableBefore < pointCloudPoolMinAvailable) {
                pointCloudPoolMinAvailable = availableBefore
            }
            if (pool === depthPool && availableBefore < depthPoolMinAvailable) {
                depthPoolMinAvailable = availableBefore
            }
            if (pool.isEmpty()) {
                if (isDepth) {
                    depthPoolStarvationEvents++
                } else {
                    pointCloudPoolStarvationEvents++
                }
                return null
            }
            val candidate = pool.removeFirst()
            val inUseAfterAcquire = if (pool === pointCloudPool) {
                pointCloudPoolCapacity - pool.size
            } else {
                depthPoolCapacity - pool.size
            }
            if (pool === pointCloudPool && inUseAfterAcquire > pointCloudPoolMaxInUse) {
                pointCloudPoolMaxInUse = inUseAfterAcquire
            }
            if (pool === depthPool && inUseAfterAcquire > depthPoolMaxInUse) {
                depthPoolMaxInUse = inUseAfterAcquire
            }
            if (candidate.size < requiredSize) {
                pool.addFirst(candidate)
                return null
            }
            return candidate
        }
    }

    private fun releaseBuffer(pool: ArrayDeque<ByteArray>, buffer: ByteArray) {
        synchronized(pool) {
            pool.addLast(buffer)
        }
    }

    private fun putIntLE(target: ByteArray, offset: Int, value: Int) {
        target[offset] = (value and 0xFF).toByte()
        target[offset + 1] = ((value ushr 8) and 0xFF).toByte()
        target[offset + 2] = ((value ushr 16) and 0xFF).toByte()
        target[offset + 3] = ((value ushr 24) and 0xFF).toByte()
    }

    private fun putLongLE(target: ByteArray, offset: Int, value: Long) {
        target[offset] = (value and 0xFF).toByte()
        target[offset + 1] = ((value ushr 8) and 0xFF).toByte()
        target[offset + 2] = ((value ushr 16) and 0xFF).toByte()
        target[offset + 3] = ((value ushr 24) and 0xFF).toByte()
        target[offset + 4] = ((value ushr 32) and 0xFF).toByte()
        target[offset + 5] = ((value ushr 40) and 0xFF).toByte()
        target[offset + 6] = ((value ushr 48) and 0xFF).toByte()
        target[offset + 7] = ((value ushr 56) and 0xFF).toByte()
    }
}
