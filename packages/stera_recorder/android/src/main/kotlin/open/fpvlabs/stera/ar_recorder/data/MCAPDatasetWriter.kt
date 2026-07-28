package open.fpvlabs.stera.ar_recorder.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import open.fpvlabs.stera.ar_recorder.sensors.ImuSample
import open.fpvlabs.stera.ar_recorder.session.DepthFrameData
import open.fpvlabs.stera.ar_recorder.session.PointCloudFrameData
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * MCAP-based dataset writer that writes spatial data as ROS2-compatible MCAP messages.
 * Implements the same DatasetWriter interface as DatasetWriterImpl.
 */
class MCAPDatasetWriter(
    private val context: Context,
    private val deviceModel: String,
    private val androidVersion: String
) : DatasetWriter {

    private companion object {
        private const val LOG_FLUSH_EVERY_N_ROWS = 30
        private const val REALTIME_FLUSH_INTERVAL_NS = 500_000_000L
        private const val TRAJECTORY_WRITE_INTERVAL_NS = 5_000_000_000L
        private const val WORLD_FRAME_ID = "world"
        private const val CAMERA_LINK_FRAME_ID = "camera_link"
        private const val CAMERA_OPTICAL_FRAME_ID = "camera_optical_frame"

        /** Cap the session thumbnail's long edge so it stays ≤1080p (1920×1080 for
         *  16:9). The source RGB frame can be 4K; embedded as base64 in the assets
         *  API payload that overflows the request body limit, so downscale first. */
        private const val THUMBNAIL_MAX_EDGE = 1920
        private val CAMERA_LINK_TO_OPTICAL_TRANSFORM = CDRSerializer.TFTransform(
            frameId = CAMERA_LINK_FRAME_ID,
            childFrameId = CAMERA_OPTICAL_FRAME_ID,
            tx = 0.0,
            ty = 0.0,
            tz = 0.0,
            qx = -0.7071067811865476,
            qy = 0.0,
            qz = -0.7071067811865476,
            qw = 0.0
        )
    }

    private var baseOutputDir: File? = null
    private var sessionDir: File? = null
    private var spatialDataDir: File? = null

    // MCAP writer
    private var mcapWriter: MCAPWriter? = null
    private var mcapFile: File? = null

    // Text writers for debugging (kept outside MCAP)
    private var frameLogWriter: BufferedWriter? = null
    private var systemLogWriter: BufferedWriter? = null

    private var isInitialized = false

    // Channel IDs
    private var poseChannelId = 0
    private var imuChannelId = 0
    private var compressedRgbChannelId = 0
    private var depthChannelId = 0
    private var pointCloudChannelId = 0
    private var meshChannelId = 0
    private var meshCloudChannelId = 0
    private var cameraInfoChannelId = 0
    private var depthCameraInfoChannelId = 0
    private var tfChannelId = 0
    private var trajectoryChannelId = 0
    private var deviceMetricsChannelId = 0

    // Counters
    private var poseCount = 0
    private var imuSampleCount = 0
    private var pointCloudCount = 0
    private var depthFrameCount = 0
    private var frameLogRows = 0
    private var skippedDepthFrames = 0

    private var totalBytesWritten = 0L
    private var freeStorageBeforeBytes = 0L
    private var freeStorageAfterBytes = 0L
    private var writerLatencyTotalNs = 0L
    private var writerLatencySamples = 0L
    private var writersPaused = false
    private var lastRealtimeFlushTimestampNs = 0L
    private var intrinsicsJsonWritten = false
    private var thumbnailSaved = false

    // Accumulated data for end-of-session writes
    private val trajectoryPoses = mutableListOf<PoseEntry>()
    private var lastTrajectoryWriteTimestampNs = 0L
    private var lastPointCloudData: ByteArray? = null
    private var lastPointCloudDataLength = 0
    private var lastPointCloudTimestamp = 0L
    private var lastPointCloudCount = 0

    override fun createSessionDirectory(baseDir: File?): File? {
        return try {
            baseOutputDir = baseDir ?: File(context.filesDir, "ar_sessions")
            val outputBase = baseOutputDir ?: return null
            if (!outputBase.exists() && !outputBase.mkdirs()) {
                println("Failed to create app storage directory: ${outputBase.absolutePath}")
                return null
            }
            if (!outputBase.canWrite()) {
                println("App storage directory is not writable: ${outputBase.absolutePath}")
                return null
            }

            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            sessionDir = File(outputBase, "session_$timestamp").apply { mkdirs() }

            if (sessionDir == null) return null

            freeStorageBeforeBytes = sessionDir?.usableSpace ?: 0L
            println("Session directory created: ${sessionDir?.absolutePath}")
            sessionDir
        } catch (e: Exception) {
            println("Failed to create session directory: ${e.message}")
            null
        }
    }

    override fun pauseWriters() {
        writersPaused = true
        try {
            mcapWriter?.forceFlushChunk()
            frameLogWriter?.flush()
            systemLogWriter?.flush()
        } catch (_: Exception) {}
    }

    override fun resumeWriters() {
        writersPaused = false
    }

    override fun deleteSessionDirectory(): Boolean {
        val directory = sessionDir ?: return false
        return try {
            finalize()
            directory.deleteRecursively()
        } catch (e: Exception) {
            println("Failed to delete session directory: ${e.message}")
            false
        } finally {
            baseOutputDir = null
            sessionDir = null
            spatialDataDir = null
            isInitialized = false
        }
    }

    override fun initializeWriters(): Boolean {
        return try {
            val session = sessionDir ?: return false

            // Initialize MCAP writer
            val sessionTimestamp = session.name.removePrefix("session_")
            val file = File(session, "session_data_$sessionTimestamp.mcap")
            mcapFile = file
            val writer = MCAPWriter()
            if (!writer.open(file, profile = "ros2", library = "fpv_labs/1.0")) {
                return false
            }
            mcapWriter = writer

            trajectoryPoses.clear()
            lastTrajectoryWriteTimestampNs = 0L
            registerSchemasAndChannels()

            isInitialized = true
            logSystem("MCAP session log initialized")
            logSystem("Device: $deviceModel")
            logSystem("Android: $androidVersion")
            true
        } catch (e: Exception) {
            println("Failed to initialize MCAP writers: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    private fun registerSchemasAndChannels() {
        val writer = mcapWriter ?: return
        val enc = ROS2SchemaDefinitions.SCHEMA_ENCODING
        val msgEnc = ROS2SchemaDefinitions.MESSAGE_ENCODING

        val poseSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.POSE_STAMPED_NAME, enc, ROS2SchemaDefinitions.POSE_STAMPED_SCHEMA
        )
        poseChannelId = writer.addChannel(
            ROS2SchemaDefinitions.POSE_TOPIC, msgEnc, poseSchemaId
        )

        val imuSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.IMU_NAME, enc, ROS2SchemaDefinitions.IMU_SCHEMA
        )
        imuChannelId = writer.addChannel(
            ROS2SchemaDefinitions.IMU_TOPIC, msgEnc, imuSchemaId
        )

        val imageSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.IMAGE_NAME, enc, ROS2SchemaDefinitions.IMAGE_SCHEMA
        )
        depthChannelId = writer.addChannel(
            ROS2SchemaDefinitions.DEPTH_TOPIC, msgEnc, imageSchemaId
        )

        val compressedImageSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.COMPRESSED_IMAGE_NAME, enc, ROS2SchemaDefinitions.COMPRESSED_IMAGE_SCHEMA
        )
        compressedRgbChannelId = writer.addChannel(
            ROS2SchemaDefinitions.COMPRESSED_RGB_TOPIC, msgEnc, compressedImageSchemaId
        )

        val pc2SchemaId = writer.addSchema(
            ROS2SchemaDefinitions.POINT_CLOUD_2_NAME, enc, ROS2SchemaDefinitions.POINT_CLOUD_2_SCHEMA
        )
        pointCloudChannelId = writer.addChannel(
            ROS2SchemaDefinitions.POINTCLOUD_TOPIC, msgEnc, pc2SchemaId
        )

        val markerSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.MARKER_NAME, enc, ROS2SchemaDefinitions.MARKER_SCHEMA
        )
        meshChannelId = writer.addChannel(
            ROS2SchemaDefinitions.MESH_TOPIC, msgEnc, markerSchemaId
        )

        // mesh_cloud reuses PointCloud2 schema
        meshCloudChannelId = writer.addChannel(
            ROS2SchemaDefinitions.MESH_CLOUD_TOPIC, msgEnc, pc2SchemaId
        )

        val camInfoSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.CAMERA_INFO_NAME, enc, ROS2SchemaDefinitions.CAMERA_INFO_SCHEMA
        )
        cameraInfoChannelId = writer.addChannel(
            ROS2SchemaDefinitions.CAMERA_INFO_TOPIC, msgEnc, camInfoSchemaId
        )
        depthCameraInfoChannelId = writer.addChannel(
            ROS2SchemaDefinitions.DEPTH_CAMERA_INFO_TOPIC, msgEnc, camInfoSchemaId
        )

        val tfSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.TF_MESSAGE_NAME, enc, ROS2SchemaDefinitions.TF_MESSAGE_SCHEMA
        )
        tfChannelId = writer.addChannel(
            ROS2SchemaDefinitions.TF_TOPIC, msgEnc, tfSchemaId
        )

        val pathSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.PATH_NAME, enc, ROS2SchemaDefinitions.PATH_SCHEMA
        )
        trajectoryChannelId = writer.addChannel(
            ROS2SchemaDefinitions.TRAJECTORY_TOPIC, msgEnc, pathSchemaId
        )

        val deviceMetricsSchemaId = writer.addSchema(
            ROS2SchemaDefinitions.DEVICE_METRICS_NAME, enc, ROS2SchemaDefinitions.DEVICE_METRICS_SCHEMA
        )
        deviceMetricsChannelId = writer.addChannel(
            ROS2SchemaDefinitions.DEVICE_METRICS_TOPIC, msgEnc, deviceMetricsSchemaId
        )
    }

    override fun logSystem(message: String) {
        if (!isInitialized || writersPaused) return
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
        val line = "[$timestamp] $message\n"
        try {
            systemLogWriter?.write(line)
            totalBytesWritten += line.toByteArray().size.toLong()
        } catch (_: Exception) {}
    }

    override fun logError(message: String, throwable: Throwable?) {
        val suffix = throwable?.message?.let { ": $it" } ?: ""
        logSystem("ERROR: $message$suffix")
    }

    override fun writeDeviceMetrics(
        timestampNs: Long,
        batteryLevel: Float,
        batteryState: Int,
        batteryStateStr: String,
        cpuUsage: Float,
        memoryUsedMb: Double,
        memoryAvailableMb: Double,
        thermalState: Int,
        thermalStateStr: String
    ) {
        if (!isInitialized || writersPaused) return
        val logTime = timestampNs
        val data = CDRSerializer.serializeDeviceMetrics(
            timestampNs = timestampNs,
            frameId = "device",
            batteryLevel = batteryLevel,
            batteryState = batteryState,
            batteryStateStr = batteryStateStr,
            cpuUsage = cpuUsage,
            memoryUsedMb = memoryUsedMb,
            memoryAvailableMb = memoryAvailableMb,
            thermalState = thermalState,
            thermalStateStr = thermalStateStr,
            deviceModel = deviceModel
        )
        mcapWriter?.addMessage(deviceMetricsChannelId, logTime, logTime, data)
        totalBytesWritten += data.size.toLong() + 22
    }

    override fun writePoseRow(timestamp: Long, pose: FloatArray, trackingState: String) {
        if (!isInitialized || writersPaused) return
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            val data = CDRSerializer.serializePoseStamped(
                timestampNs = timestamp,
                frameId = WORLD_FRAME_ID,
                tx = pose[0], ty = pose[1], tz = pose[2],
                qx = pose[3], qy = pose[4], qz = pose[5], qw = pose[6]
            )
            mcapWriter?.addMessage(poseChannelId, timestamp, timestamp, data)
            poseCount++
            totalBytesWritten += data.size + 22

            // Write per-frame TF (world -> camera_link -> camera_optical_frame)
            val tfData = CDRSerializer.serializeTFMessage(
                timestampNs = timestamp,
                transforms = listOf(
                    CDRSerializer.TFTransform(
                        frameId = WORLD_FRAME_ID,
                        childFrameId = CAMERA_LINK_FRAME_ID,
                        tx = pose[0].toDouble(),
                        ty = pose[1].toDouble(),
                        tz = pose[2].toDouble(),
                        qx = pose[3].toDouble(),
                        qy = pose[4].toDouble(),
                        qz = pose[5].toDouble(),
                        qw = pose[6].toDouble()
                    ),
                    CAMERA_LINK_TO_OPTICAL_TRANSFORM
                )
            )
            mcapWriter?.addMessage(tfChannelId, timestamp, timestamp, tfData)
            totalBytesWritten += tfData.size + 22

            // Match iOS by emitting rolling Path snapshots during recording.
            trajectoryPoses.add(PoseEntry(timestamp, pose[0], pose[1], pose[2], pose[3], pose[4], pose[5], pose[6]))
            maybeWriteTrajectorySnapshot(timestamp)
        } catch (e: Exception) {
            logError("Failed to write pose", e)
        } finally {
            recordWriterLatency(startNs)
        }
    }

    override fun writeImuSamples(samples: List<ImuSample>) {
        if (!isInitialized || writersPaused || samples.isEmpty()) return
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            for (sample in samples) {
                val data = CDRSerializer.serializeImu(
                    timestampNs = sample.timestampNs,
                    frameId = "device",
                    angularVelocity = Triple(
                        sample.gyroX.toDouble(), sample.gyroY.toDouble(), sample.gyroZ.toDouble()
                    ),
                    linearAcceleration = Triple(
                        sample.accelX.toDouble(), sample.accelY.toDouble(), sample.accelZ.toDouble()
                    )
                )
                mcapWriter?.addMessage(imuChannelId, sample.timestampNs, sample.timestampNs, data)
                imuSampleCount++
                totalBytesWritten += data.size + 22
            }
        } catch (e: Exception) {
            logError("Failed to write IMU samples", e)
        } finally {
            recordWriterLatency(startNs)
        }
    }

    /**
     * Downscale a full-size JPEG frame to a ≤1080p thumbnail (long edge capped at
     * [THUMBNAIL_MAX_EDGE]) so it stays small on disk and when base64-embedded in
     * the assets-registration payload. Returns the original bytes unchanged if
     * decoding fails or the re-encoded result is not smaller than the source.
     */
    private fun makeThumbnailJpeg(jpegData: ByteArray): ByteArray {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(jpegData, 0, jpegData.size, bounds)
            val longEdge = maxOf(bounds.outWidth, bounds.outHeight)
            if (longEdge <= 0) return jpegData

            // Coarse power-of-two downsample keeps peak decode memory low.
            var sample = 1
            while (longEdge / (sample * 2) >= THUMBNAIL_MAX_EDGE) sample *= 2
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
            val decoded = BitmapFactory.decodeByteArray(jpegData, 0, jpegData.size, decodeOpts)
                ?: return jpegData

            // Fine scale so the long edge lands exactly at the cap (never upscale).
            val decodedLong = maxOf(decoded.width, decoded.height)
            val scaled = if (decodedLong > THUMBNAIL_MAX_EDGE) {
                val ratio = THUMBNAIL_MAX_EDGE.toFloat() / decodedLong
                Bitmap.createScaledBitmap(
                    decoded,
                    (decoded.width * ratio).toInt().coerceAtLeast(1),
                    (decoded.height * ratio).toInt().coerceAtLeast(1),
                    true,
                )
            } else {
                decoded
            }

            val out = java.io.ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
            if (scaled !== decoded) scaled.recycle()
            decoded.recycle()

            val result = out.toByteArray()
            if (result.size < jpegData.size) result else jpegData
        } catch (e: Exception) {
            println("Failed to downscale thumbnail: ${e.message}")
            jpegData
        }
    }

    override fun writeCompressedRgbFrame(timestamp: Long, jpegData: ByteArray) {
        if (!isInitialized || writersPaused) return
        // Save first JPEG frame as thumbnail
        if (!thumbnailSaved) {
            try {
                sessionDir?.let { dir ->
                    File(dir, "thumbnail.jpg").writeBytes(makeThumbnailJpeg(jpegData))
                    thumbnailSaved = true
                    println("thumbnail.jpg saved in ${dir.absolutePath}")
                }
            } catch (e: Exception) {
                println("Failed to save thumbnail: ${e.message}")
            }
        }
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            val data = CDRSerializer.serializeCompressedImage(
                timestampNs = timestamp,
                frameId = CAMERA_OPTICAL_FRAME_ID,
                format = "jpeg",
                imageData = jpegData
            )
            mcapWriter?.addMessage(compressedRgbChannelId, timestamp, timestamp, data)
            totalBytesWritten += data.size + 22
        } catch (e: Exception) {
            logError("Failed to write compressed RGB frame", e)
        } finally {
            recordWriterLatency(startNs)
        }
    }

    override fun writeFrameLogRow(
        frameIndex: Int,
        globalArFrameIndex: Int,
        arcoreTimestampNs: Long,
        trackingState: String,
        encoded: Boolean,
        depthAvailable: Boolean,
        pointCloudAvailable: Boolean
    ) {
        if (!isInitialized || writersPaused) return
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            val line = "$frameIndex,$globalArFrameIndex,$arcoreTimestampNs,$trackingState,${if (encoded) 1 else 0},${if (depthAvailable) 1 else 0},${if (pointCloudAvailable) 1 else 0}\n"
            frameLogWriter?.write(line)
            frameLogRows++
            totalBytesWritten += line.toByteArray().size.toLong()
            if (frameLogRows % LOG_FLUSH_EVERY_N_ROWS == 0) {
                frameLogWriter?.flush()
                systemLogWriter?.flush()
            }
        } catch (_: Exception) {
        } finally {
            recordWriterLatency(startNs)
        }
    }

    override fun logTrackingStateTransition(previousState: String, nextState: String, timestampNs: Long) {
        logSystem("Tracking state transition: $previousState -> $nextState at $timestampNs ns")
    }

    override fun writePointCloud(timestamp: Long, frameData: PointCloudFrameData?) {
        if (!isInitialized || frameData == null) return
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            // Binary format: [int64 timestamp][int32 pointCount][point data...]
            val headerSize = 12
            if (frameData.validSize <= headerSize) return

            val pointData = frameData.bytes.copyOfRange(headerSize, frameData.validSize)
            val data = CDRSerializer.serializePointCloud2(
                timestampNs = timestamp,
                frameId = WORLD_FRAME_ID,
                pointCount = frameData.pointCount,
                pointData = pointData,
                pointDataOffset = 0,
                pointDataLength = pointData.size
            )
            mcapWriter?.addMessage(pointCloudChannelId, timestamp, timestamp, data)
            totalBytesWritten += data.size + 22

            // Keep latest snapshot for compatibility stats/introspection
            lastPointCloudData = pointData
            lastPointCloudDataLength = pointData.size
            lastPointCloudTimestamp = timestamp
            lastPointCloudCount = frameData.pointCount
            pointCloudCount++

            if (frameData.pointCount <= 0) {
                logSystem("WARN: point cloud frame $timestamp has no points")
            }
        } catch (e: Exception) {
            logError("Failed to write point cloud", e)
        } finally {
            recordWriterLatency(startNs)
            frameData.release()
        }
    }

    override fun writeDepthFrame(timestamp: Long, frameData: DepthFrameData?): Boolean {
        if (!isInitialized || frameData == null) return false
        val startNs = SystemClock.elapsedRealtimeNanos()
        val expectedSize = frameData.width * frameData.height * frameData.bytesPerPixel
        if (frameData.validSize != expectedSize) {
            skippedDepthFrames++
            logSystem("WARN: skipping depth frame $timestamp, invalid size ${frameData.validSize}, expected $expectedSize")
            frameData.release()
            return false
        }

        return try {
            val data = CDRSerializer.serializeImage(
                timestampNs = timestamp,
                frameId = CAMERA_OPTICAL_FRAME_ID,
                height = frameData.height,
                width = frameData.width,
                encoding = "16UC1",
                isBigEndian = false,
                step = frameData.width * frameData.bytesPerPixel,
                imageData = frameData.bytes,
                imageDataLength = frameData.validSize
            )
            mcapWriter?.addMessage(depthChannelId, timestamp, timestamp, data)
            depthFrameCount++
            totalBytesWritten += data.size + 22
            true
        } catch (e: Exception) {
            logError("Failed to write depth frame", e)
            false
        } finally {
            recordWriterLatency(startNs)
            frameData.release()
        }
    }

    override fun writeIntrinsics(timestampNs: Long, intrinsics: Map<String, Any>) {
        if (!isInitialized) return

        try {
            val fx = (intrinsics["focalLengthX"] as? Number)?.toDouble() ?: 0.0
            val fy = (intrinsics["focalLengthY"] as? Number)?.toDouble() ?: 0.0
            val cx = (intrinsics["principalPointX"] as? Number)?.toDouble() ?: 0.0
            val cy = (intrinsics["principalPointY"] as? Number)?.toDouble() ?: 0.0
            val w = (intrinsics["imageWidth"] as? Number)?.toInt() ?: 0
            val h = (intrinsics["imageHeight"] as? Number)?.toInt() ?: 0

            val data = CDRSerializer.serializeCameraInfo(
                timestampNs = timestampNs,
                frameId = CAMERA_OPTICAL_FRAME_ID,
                height = h,
                width = w,
                fx = fx, fy = fy, cx = cx, cy = cy
            )
            mcapWriter?.addMessage(cameraInfoChannelId, timestampNs, timestampNs, data)
            totalBytesWritten += data.size + 22

            intrinsicsJsonWritten = true
        } catch (e: Exception) {
            logError("Failed to write intrinsics", e)
        }
    }

    override fun writeDepthIntrinsics(timestampNs: Long, intrinsics: Map<String, Any>) {
        if (!isInitialized) return

        try {
            val fx = (intrinsics["focalLengthX"] as? Number)?.toDouble() ?: 0.0
            val fy = (intrinsics["focalLengthY"] as? Number)?.toDouble() ?: 0.0
            val cx = (intrinsics["principalPointX"] as? Number)?.toDouble() ?: 0.0
            val cy = (intrinsics["principalPointY"] as? Number)?.toDouble() ?: 0.0
            val w = (intrinsics["imageWidth"] as? Number)?.toInt() ?: 0
            val h = (intrinsics["imageHeight"] as? Number)?.toInt() ?: 0

            val data = CDRSerializer.serializeCameraInfo(
                timestampNs = timestampNs,
                frameId = CAMERA_OPTICAL_FRAME_ID,
                height = h,
                width = w,
                fx = fx, fy = fy, cx = cx, cy = cy
            )
            mcapWriter?.addMessage(depthCameraInfoChannelId, timestampNs, timestampNs, data)
            totalBytesWritten += data.size + 22
        } catch (e: Exception) {
            logError("Failed to write depth intrinsics", e)
        }
    }

    override fun writeMetadata(metadata: Map<String, Any?>) {
        if (!isInitialized) return
        try {
            // Write as MCAP metadata record
            val flat = mutableMapOf<String, String>()
            flattenMetadata(metadata, "", flat)
            mcapWriter?.addMetadata("session_metadata", flat)

            // Write JSON to session root
            val session = sessionDir ?: return
            val json = toJsonValue(metadata, 0)
            File(session, "metadata.json").writeText(json)
            totalBytesWritten += json.toByteArray().size.toLong()
            logSystem("metadata.json written")
        } catch (e: Exception) {
            logError("Failed to write metadata", e)
        }
    }

    override fun writeSessionSummary(summaryText: String) {
        if (!isInitialized) return
        try {
            val dataDir = spatialDataDir ?: return
            File(dataDir, "session_summary.txt").writeText(summaryText)
            totalBytesWritten += summaryText.toByteArray().size.toLong()
            logSystem("session_summary.txt written")
        } catch (e: Exception) {
            logError("Failed to write session summary", e)
        }
    }

    override fun writeFrameDropLog(dropLog: Map<String, Any?>): String? {
        if (!isInitialized) return null
        return try {
            val dataDir = spatialDataDir ?: return null
            val file = File(dataDir, "frame_drop_log.json")
            file.writeText(toJsonValue(dropLog, 0))
            totalBytesWritten += file.length()
            logSystem("frame_drop_log.json written")
            file.name
        } catch (e: Exception) {
            logError("Failed to write frame_drop_log.json", e)
            null
        }
    }

    override fun addVideoBytesWritten(videoBytes: Long) {
        if (videoBytes > 0) totalBytesWritten += videoBytes
    }

    override fun getVideoOutputPath(): String? = null

    override fun getSessionDirectory(): String? = sessionDir?.absolutePath

    override fun getRecordingStats(): Map<String, Any> = mapOf(
        "poseCount" to poseCount,
        "imuSampleCount" to imuSampleCount,
        "pointCloudCount" to pointCloudCount,
        "depthFrameCount" to depthFrameCount,
        "skippedDepthFrames" to skippedDepthFrames,
        "totalBytesWritten" to totalBytesWritten
    )

    override fun getFreeStorageBeforeBytes(): Long = freeStorageBeforeBytes
    override fun getFreeStorageAfterBytes(): Long = freeStorageAfterBytes

    override fun getWriterAverageLatencyMs(): Double {
        if (writerLatencySamples <= 0L) return 0.0
        return (writerLatencyTotalNs.toDouble() / writerLatencySamples.toDouble()) / 1_000_000.0
    }

    override fun flushRealtimeData(timestampNs: Long) {
        if (!isInitialized || writersPaused) return
        if (timestampNs - lastRealtimeFlushTimestampNs < REALTIME_FLUSH_INTERVAL_NS) return
        lastRealtimeFlushTimestampNs = timestampNs
        try {
            mcapWriter?.forceFlushChunk()
            frameLogWriter?.flush()
            systemLogWriter?.flush()
        } catch (_: Exception) {
        }
    }

    override fun captureFreeStorageAfterSnapshot() {
        freeStorageAfterBytes = sessionDir?.usableSpace ?: 0L
    }

    override fun createSpatialDataZip(): Triple<Boolean, String?, String?> {
        val session = sessionDir ?: return Triple(false, null, "sessionDir is null")
        val file = mcapFile ?: return Triple(false, null, "mcapFile is null")

        return try {
            // Flush text writers
            frameLogWriter?.flush(); frameLogWriter?.close(); frameLogWriter = null
            systemLogWriter?.flush(); systemLogWriter?.close(); systemLogWriter = null

            // Write end-of-session messages
            writeEndOfSessionMessages()

            // Finalize MCAP
            mcapWriter?.finish()
            mcapWriter = null

            if (!file.exists() || file.length() == 0L) {
                return Triple(false, null, "session_data.mcap is empty or missing")
            }

            println("session finalized at ${session.absolutePath}")
            Triple(true, session.absolutePath, null)
        } catch (e: Exception) {
            println("Failed to finalize session: ${e.message}")
            e.printStackTrace()
            Triple(false, null, e.message)
        }
    }

    override fun finalize() {
        try {
            frameLogWriter?.flush(); frameLogWriter?.close(); frameLogWriter = null
            systemLogWriter?.flush(); systemLogWriter?.close(); systemLogWriter = null
            writeEndOfSessionMessages()
            mcapWriter?.finish(); mcapWriter = null
            freeStorageAfterBytes = sessionDir?.usableSpace ?: 0L
            isInitialized = false
            println("MCAP dataset writers finalized")
        } catch (e: Exception) {
            println("Failed to finalize MCAP writers: ${e.message}")
        }
    }

    override fun release() {
        finalize()
        baseOutputDir = null
        sessionDir = null
        spatialDataDir = null
        poseCount = 0
        imuSampleCount = 0
        pointCloudCount = 0
        depthFrameCount = 0
        frameLogRows = 0
        skippedDepthFrames = 0
        totalBytesWritten = 0L
        freeStorageBeforeBytes = 0L
        freeStorageAfterBytes = 0L
        writerLatencyTotalNs = 0L
        writerLatencySamples = 0L
        writersPaused = false
        intrinsicsJsonWritten = false
        thumbnailSaved = false
        mcapWriter = null
        mcapFile = null
        lastRealtimeFlushTimestampNs = 0L
        trajectoryPoses.clear()
        lastTrajectoryWriteTimestampNs = 0L
        lastPointCloudData = null
        lastPointCloudDataLength = 0
        lastPointCloudTimestamp = 0L
        lastPointCloudCount = 0
        println("MCAP dataset writer released")
    }

    private fun writeEndOfSessionMessages() {
        val lastTimestamp = trajectoryPoses.lastOrNull()?.timestampNs ?: return

        // Always write one final snapshot so stop captures the latest pose list.
        writeTrajectorySnapshot(lastTimestamp)

        // Note: Mesh and mesh_cloud channels are registered but may be empty on Android
        // if ARCore doesn't provide mesh data for this session
    }

    private fun maybeWriteTrajectorySnapshot(timestamp: Long) {
        if (trajectoryPoses.isEmpty()) return
        if (timestamp - lastTrajectoryWriteTimestampNs < TRAJECTORY_WRITE_INTERVAL_NS) return

        lastTrajectoryWriteTimestampNs = timestamp
        writeTrajectorySnapshot(timestamp)
    }

    private fun writeTrajectorySnapshot(timestamp: Long) {
        val writer = mcapWriter ?: return
        if (trajectoryPoses.isEmpty()) return

        val data = CDRSerializer.serializePath(
            timestampNs = timestamp,
            frameId = WORLD_FRAME_ID,
            poses = trajectoryPoses
        )
        writer.addMessage(trajectoryChannelId, timestamp, timestamp, data)
        totalBytesWritten += data.size + 22
    }

    private fun recordWriterLatency(startNs: Long) {
        val elapsedNs = SystemClock.elapsedRealtimeNanos() - startNs
        if (elapsedNs > 0L) {
            writerLatencyTotalNs += elapsedNs
            writerLatencySamples++
        }
    }

    private fun flattenMetadata(map: Map<String, Any?>, prefix: String, result: MutableMap<String, String>) {
        for ((key, value) in map) {
            val fullKey = if (prefix.isEmpty()) key else "$prefix.$key"
            when (value) {
                is Map<*, *> -> {
                    @Suppress("UNCHECKED_CAST")
                    flattenMetadata(value as Map<String, Any?>, fullKey, result)
                }
                null -> result[fullKey] = "null"
                else -> result[fullKey] = value.toString()
            }
        }
    }

    private fun toJsonValue(value: Any?, level: Int): String {
        return when (value) {
            null -> "null"
            is String -> "\"${escapeJson(value)}\""
            is Number, is Boolean -> value.toString()
            is Map<*, *> -> {
                if (value.isEmpty()) return "{}"
                val indent = "  ".repeat(level)
                val childIndent = "  ".repeat(level + 1)
                val entries = value.entries.joinToString(",\n") { entry ->
                    val key = entry.key?.toString() ?: "null"
                    "$childIndent\"${escapeJson(key)}\": ${toJsonValue(entry.value, level + 1)}"
                }
                "{\n$entries\n$indent}"
            }
            is List<*> -> {
                if (value.isEmpty()) return "[]"
                val indent = "  ".repeat(level)
                val childIndent = "  ".repeat(level + 1)
                val entries = value.joinToString(",\n") { "$childIndent${toJsonValue(it, level + 1)}" }
                "[\n$entries\n$indent]"
            }
            else -> "\"${escapeJson(value.toString())}\""
        }
    }

    private fun escapeJson(raw: String): String = raw
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}
