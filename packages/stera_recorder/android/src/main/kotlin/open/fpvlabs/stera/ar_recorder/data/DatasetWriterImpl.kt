package open.fpvlabs.stera.ar_recorder.data

import android.content.Context
import android.os.SystemClock
import open.fpvlabs.stera.ar_recorder.sensors.ImuSample
import open.fpvlabs.stera.ar_recorder.session.DepthFrameData
import open.fpvlabs.stera.ar_recorder.session.PointCloudFrameData
import java.io.BufferedOutputStream
import java.io.BufferedWriter
import java.io.File
import java.io.FileOutputStream
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Writes AR recording data to files: video, CSVs, JSON, and binary pointcloud/depth payloads.
 * Runs on a dedicated HandlerThread.
 */
class DatasetWriterImpl(
    private val context: Context,
    private val deviceModel: String,
    private val androidVersion: String
) : DatasetWriter {

    private companion object {
        private const val LOG_FLUSH_EVERY_N_ROWS = 30
    }

    private var baseOutputDir: File? = null
    private var sessionDir: File? = null
    private var spatialDataDir: File? = null

    private var posesWriter: BufferedWriter? = null
    private var imuWriter: BufferedWriter? = null
    private var frameLogWriter: BufferedWriter? = null
    private var systemLogWriter: BufferedWriter? = null

    private var isInitialized: Boolean = false

    private var poseCount: Int = 0
    private var imuSampleCount: Int = 0
    private var pointCloudCount: Int = 0
    private var depthFrameCount: Int = 0
    private var frameLogRows: Int = 0
    private var skippedDepthFrames: Int = 0

    private var totalBytesWritten: Long = 0L
    private var freeStorageBeforeBytes: Long = 0L
    private var freeStorageAfterBytes: Long = 0L
    private var depthFormatWritten: Boolean = false
    private var pointcloudFormatWritten: Boolean = false
    private var writerLatencyTotalNs: Long = 0L
    private var writerLatencySamples: Long = 0L
    private var writersPaused: Boolean = false
    private var zipStream: ZipOutputStream? = null

    /**
     * Creates the output directory structure for a recording session.
     */
    override fun createSessionDirectory(baseDir: File?): File? {
        return try {
            baseOutputDir = baseDir ?: File(context.filesDir, "ar_sessions")
            val outputBase = baseOutputDir ?: return null
            if (!outputBase.exists() && !outputBase.mkdirs()) {
                println("❌ Failed to create app storage directory: ${outputBase.absolutePath}")
                return null
            }
            if (!outputBase.canWrite()) {
                println("❌ App storage directory is not writable: ${outputBase.absolutePath}")
                return null
            }

            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            sessionDir = File(outputBase, "session_$timestamp").apply {
                mkdirs()
            }
            spatialDataDir = sessionDir?.let { session ->
                File(session, "spatial_data").apply {
                    mkdirs()
                }
            }

            if (sessionDir == null || spatialDataDir == null) {
                println("❌ Failed to create session directory structure")
                return null
            }

            freeStorageBeforeBytes = sessionDir?.usableSpace ?: 0L

            println("✅ Session directory created: ${sessionDir?.absolutePath}")
            println("✅ Spatial data directory created: ${spatialDataDir?.absolutePath}")
            sessionDir
        } catch (e: Exception) {
            println("❌ Failed to create session directory: ${e.message}")
            e.printStackTrace()
            null
        }
    }

    override fun pauseWriters() {
        writersPaused = true
        try {
            posesWriter?.flush()
            imuWriter?.flush()
            frameLogWriter?.flush()
            systemLogWriter?.flush()
        } catch (_: Exception) {
        }
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
            println("❌ Failed to delete session directory: ${e.message}")
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
            val dataDir = spatialDataDir ?: return false

            posesWriter = BufferedWriter(FileWriter(File(dataDir, "poses.csv"))).apply {
                write("timestamp_ns,tx,ty,tz,qx,qy,qz,qw,tracking_state\n")
            }

            imuWriter = BufferedWriter(FileWriter(File(dataDir, "imu.csv"))).apply {
                write("timestamp_ns,sensor_type,x,y,z,accuracy\n")
            }

            frameLogWriter = BufferedWriter(FileWriter(File(dataDir, "frame_log.csv"))).apply {
                write("frame_index,global_ar_frame_index,arcore_timestamp_ns,tracking_state,encoded,depth_available,pointcloud_available\n")
            }

            systemLogWriter = BufferedWriter(FileWriter(File(dataDir, "system_log.txt"))).apply {
                write("FPV Labs AR Recorder System Log\n")
                write("================================\n")
            }

            val session = sessionDir ?: return false
            val sessionTimestamp = session.name.removePrefix("session_")
            zipStream = ZipOutputStream(BufferedOutputStream(FileOutputStream(File(session, "session_data_${sessionTimestamp}.zip"))))

            writePointCloudFormatIfNeeded()

            isInitialized = true
            logSystem("Session log initialized")
            logSystem("Device: $deviceModel")
            logSystem("Android: $androidVersion")
            true
        } catch (e: Exception) {
            println("❌ Failed to initialize writers: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    override fun logSystem(message: String) {
        if (!isInitialized || writersPaused) return
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
        val line = "[$timestamp] $message\n"
        try {
            systemLogWriter?.write(line)
            totalBytesWritten += line.toByteArray().size.toLong()
            if (frameLogRows % LOG_FLUSH_EVERY_N_ROWS == 0) {
                systemLogWriter?.flush()
            }
        } catch (e: Exception) {
            println("❌ Failed to write system log: ${e.message}")
        }
    }

    override fun logError(message: String, throwable: Throwable?) {
        val suffix = throwable?.message?.let { ": $it" } ?: ""
        logSystem("ERROR: $message$suffix")
    }

    override fun writePoseRow(timestamp: Long, pose: FloatArray, trackingState: String) {
        if (!isInitialized || writersPaused) return
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            val line = StringBuilder().apply {
                append(timestamp)
                append(",")
                append(pose[0])
                append(",")
                append(pose[1])
                append(",")
                append(pose[2])
                append(",")
                append(pose[3])
                append(",")
                append(pose[4])
                append(",")
                append(pose[5])
                append(",")
                append(pose[6])
                append(",")
                append(trackingState)
                append("\n")
            }.toString()
            posesWriter?.write(line)
            poseCount++
            totalBytesWritten += line.toByteArray().size.toLong()
        } catch (e: Exception) {
            logError("Failed to write pose row", e)
            e.printStackTrace()
        } finally {
            recordWriterLatency(startNs)
        }
    }

    override fun writeImuSamples(samples: List<ImuSample>) {
        if (!isInitialized || writersPaused || samples.isEmpty()) return
        val startNs = SystemClock.elapsedRealtimeNanos()

        try {
            val sb = StringBuilder()
            for (sample in samples) {
                sb.append(sample.timestampNs)
                sb.append(",")
                sb.append(sample.accelX)
                sb.append(",")
                sb.append(sample.accelY)
                sb.append(",")
                sb.append(sample.accelZ)
                sb.append(",")
                sb.append(sample.gyroX)
                sb.append(",")
                sb.append(sample.gyroY)
                sb.append(",")
                sb.append(sample.gyroZ)
                sb.append("\n")
                imuSampleCount++
            }
            val payload = sb.toString()
            imuWriter?.write(payload)
            totalBytesWritten += payload.toByteArray().size.toLong()
        } catch (e: Exception) {
            logError("Failed to write IMU samples", e)
            e.printStackTrace()
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
        } catch (e: Exception) {
            logError("Failed to write frame log", e)
        } finally {
            recordWriterLatency(startNs)
        }
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
        // Legacy writer does not write device metrics
    }

    override fun logTrackingStateTransition(previousState: String, nextState: String, timestampNs: Long) {
        logSystem("Tracking state transition: $previousState -> $nextState at $timestampNs ns")
    }

    override fun writePointCloud(timestamp: Long, frameData: PointCloudFrameData?) {
        if (!isInitialized || frameData == null) return
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            writePointCloudFormatIfNeeded()
            writeZipEntry("pointcloud/frame_$timestamp.bin", frameData.bytes, 0, frameData.validSize)
            pointCloudCount++
            totalBytesWritten += frameData.validSize
            if (frameData.pointCount <= 0) {
                logSystem("WARN: point cloud frame $timestamp has no points")
            }
        } catch (e: Exception) {
            logError("Failed to write point cloud", e)
            e.printStackTrace()
        } finally {
            recordWriterLatency(startNs)
            frameData.release()
        }
    }

    override fun writeCompressedRgbFrame(timestamp: Long, jpegData: ByteArray) {
        // No-op for legacy writer — RGB is handled as video file
    }

    override fun writeDepthFrame(timestamp: Long, frameData: DepthFrameData?): Boolean {
        if (!isInitialized || frameData == null) return false
        val startNs = SystemClock.elapsedRealtimeNanos()

        val expectedSize = frameData.width * frameData.height * frameData.bytesPerPixel
        if (frameData.validSize != expectedSize) {
            skippedDepthFrames++
            logSystem(
                "WARN: skipping depth frame $timestamp, invalid size ${frameData.validSize}, expected $expectedSize " +
                    "(width=${frameData.width} height=${frameData.height} bpp=${frameData.bytesPerPixel} " +
                    "pixelStride=${frameData.pixelStride} rowStride=${frameData.rowStride})"
            )
            frameData.release()
            return false
        }

        try {
            writeDepthFormatIfNeeded(
                frameData.width,
                frameData.height,
                frameData.bytesPerPixel,
                frameData.pixelStride,
                frameData.rowStride,
                frameData.unit
            )
            writeZipEntry("depth/frame_$timestamp.bin", frameData.bytes, 0, frameData.validSize)
            depthFrameCount++
            totalBytesWritten += frameData.validSize
            return true
        } catch (e: Exception) {
            logError("Failed to write depth frame", e)
            e.printStackTrace()
            return false
        } finally {
            recordWriterLatency(startNs)
            frameData.release()
        }
    }

    override fun writeDepthIntrinsics(timestampNs: Long, intrinsics: Map<String, Any>) {
        // No-op for JSON-only writer
    }

    override fun writeIntrinsics(timestampNs: Long, intrinsics: Map<String, Any>) {
        if (!isInitialized) return
        try {
            val json = StringBuilder().apply {
                append("{\n")
                append("  \"focalLengthX\": ${intrinsics["focalLengthX"]},\n")
                append("  \"focalLengthY\": ${intrinsics["focalLengthY"]},\n")
                append("  \"principalPointX\": ${intrinsics["principalPointX"]},\n")
                append("  \"principalPointY\": ${intrinsics["principalPointY"]},\n")
                append("  \"imageWidth\": ${intrinsics["imageWidth"]},\n")
                append("  \"imageHeight\": ${intrinsics["imageHeight"]},\n")
                append("  \"distortionCoeffs\": []\n")
                append("}")
            }.toString()
            val dataDir = spatialDataDir ?: return
            val file = File(dataDir, "intrinsics.json")
            file.writeText(json)
            totalBytesWritten += file.length()
        } catch (e: Exception) {
            logError("Failed to write intrinsics", e)
            e.printStackTrace()
        }
    }

    override fun writeMetadata(metadata: Map<String, Any?>) {
        if (!isInitialized) return
        try {
            val json = toJsonValue(metadata, 0)
            val dataDir = spatialDataDir ?: return
            val file = File(dataDir, "metadata.json")
            file.writeText(json)
            totalBytesWritten += file.length()
            logSystem("metadata.json written")
        } catch (e: Exception) {
            logError("Failed to write metadata", e)
            e.printStackTrace()
        }
    }

    override fun writeSessionSummary(summaryText: String) {
        if (!isInitialized) return
        try {
            val dataDir = spatialDataDir ?: return
            val file = File(dataDir, "session_summary.txt")
            file.writeText(summaryText)
            totalBytesWritten += file.length()
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
        if (videoBytes > 0) {
            totalBytesWritten += videoBytes
        }
    }

    override fun getVideoOutputPath(): String? {
        return sessionDir?.let { dir ->
            val timestamp = dir.name.removePrefix("session_")
            File(dir, "video_$timestamp.mp4").absolutePath
        }
    }

    override fun getSessionDirectory(): String? {
        return sessionDir?.absolutePath
    }

    override fun getRecordingStats(): Map<String, Any> {
        return mapOf(
            "poseCount" to poseCount,
            "imuSampleCount" to imuSampleCount,
            "pointCloudCount" to pointCloudCount,
            "depthFrameCount" to depthFrameCount,
            "skippedDepthFrames" to skippedDepthFrames,
            "totalBytesWritten" to totalBytesWritten
        )
    }

    override fun getFreeStorageBeforeBytes(): Long = freeStorageBeforeBytes

    override fun getFreeStorageAfterBytes(): Long = freeStorageAfterBytes

    override fun getWriterAverageLatencyMs(): Double {
        if (writerLatencySamples <= 0L) return 0.0
        return (writerLatencyTotalNs.toDouble() / writerLatencySamples.toDouble()) / 1_000_000.0
    }

    override fun flushRealtimeData(timestampNs: Long) {
        if (!isInitialized || writersPaused) return
        try {
            posesWriter?.flush()
            imuWriter?.flush()
            frameLogWriter?.flush()
            systemLogWriter?.flush()
        } catch (_: Exception) {
        }
    }

    override fun captureFreeStorageAfterSnapshot() {
        freeStorageAfterBytes = sessionDir?.usableSpace ?: 0L
    }

    override fun finalize() {
        try {
            posesWriter?.flush()
            posesWriter?.close()
            posesWriter = null

            imuWriter?.flush()
            imuWriter?.close()
            imuWriter = null

            frameLogWriter?.flush()
            frameLogWriter?.close()
            frameLogWriter = null

            systemLogWriter?.flush()
            systemLogWriter?.close()
            systemLogWriter = null

            try {
                zipStream?.close()
            } catch (_: Exception) {}
            zipStream = null

            freeStorageAfterBytes = sessionDir?.usableSpace ?: 0L
            isInitialized = false
            println("✅ Dataset writers finalized")
        } catch (e: Exception) {
            println("❌ Failed to finalize writers: ${e.message}")
            e.printStackTrace()
        }
    }

    /**
     * Finalizes the incremental spatial_data.zip by adding remaining text files
     * (CSVs, JSON, TXT) from spatial_data/, then closes the zip stream and
     * cleans up the spatial_data/ directory.
     *
     * Binary .bin files were already written directly to the zip during recording.
     */
    override fun createSpatialDataZip(): Triple<Boolean, String?, String?> {
        val dataDir = spatialDataDir ?: return Triple(false, null, "spatialDataDir is null")
        val session = sessionDir ?: return Triple(false, null, "sessionDir is null")
        val sessionTimestamp = session.name.removePrefix("session_")
        val zipFile = File(session, "session_data_${sessionTimestamp}.zip")

        return try {
            // Flush and close text writers so their files are complete before adding to zip
            posesWriter?.flush(); posesWriter?.close(); posesWriter = null
            imuWriter?.flush(); imuWriter?.close(); imuWriter = null
            frameLogWriter?.flush(); frameLogWriter?.close(); frameLogWriter = null
            systemLogWriter?.flush(); systemLogWriter?.close(); systemLogWriter = null

            val zos = zipStream ?: return Triple(false, null, "zipStream is null")

            // Add remaining text files from spatial_data/ directory to the zip
            val textFiles = dataDir.walkTopDown().filter { it.isFile }.toList()
            for (file in textFiles) {
                val relativePath = file.relativeTo(dataDir).path
                val entry = ZipEntry(relativePath)
                zos.putNextEntry(entry)
                file.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }

            zos.flush()
            zos.close()
            zipStream = null

            if (!zipFile.exists() || zipFile.length() == 0L) {
                return Triple(false, null, "session_data zip is empty or missing after finalization")
            }

            // Copy metadata.json to session root so it can be read without extracting the zip
            val metadataFile = File(dataDir, "metadata.json")
            if (metadataFile.exists()) {
                metadataFile.copyTo(File(session, "metadata.json"), overwrite = true)
            }

            dataDir.deleteRecursively()
            println("✅ session_data zip created: ${zipFile.absolutePath}")
            Triple(true, zipFile.absolutePath, null)
        } catch (e: Exception) {
            println("❌ Failed to finalize session_data zip: ${e.message}")
            e.printStackTrace()
            Triple(false, null, e.message)
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
        depthFormatWritten = false
        pointcloudFormatWritten = false
        writerLatencyTotalNs = 0L
        writerLatencySamples = 0L
        writersPaused = false
        zipStream = null
        println("✅ Dataset writer released")
    }

    private fun writeZipEntry(path: String, data: ByteArray, offset: Int, length: Int) {
        val zos = zipStream ?: return
        val entry = ZipEntry(path)
        entry.method = ZipEntry.STORED
        entry.size = length.toLong()
        entry.compressedSize = length.toLong()
        val crc = CRC32()
        crc.update(data, offset, length)
        entry.crc = crc.value
        zos.putNextEntry(entry)
        zos.write(data, offset, length)
        zos.closeEntry()
    }

    private fun writeZipEntryFromString(path: String, content: String) {
        val bytes = content.toByteArray(Charsets.UTF_8)
        writeZipEntry(path, bytes, 0, bytes.size)
    }

    private fun recordWriterLatency(startNs: Long) {
        val elapsedNs = SystemClock.elapsedRealtimeNanos() - startNs
        if (elapsedNs > 0L) {
            writerLatencyTotalNs += elapsedNs
            writerLatencySamples++
        }
    }

    private fun writeDepthFormatIfNeeded(
        width: Int,
        height: Int,
        bytesPerPixel: Int,
        pixelStride: Int,
        rowStride: Int,
        unit: String
    ) {
        if (depthFormatWritten) return
        val json = """
            {
              "width": $width,
              "height": $height,
              "bytes_per_pixel": $bytesPerPixel,
              "format": "uint16",
              "unit": "$unit",
              "endianness": "little",
              "source_pixel_stride": $pixelStride,
              "source_row_stride": $rowStride,
              "includes_padding": false
            }
        """.trimIndent()
        writeZipEntryFromString("depth_format.json", json)
        totalBytesWritten += json.toByteArray().size.toLong()
        depthFormatWritten = true
        logSystem("depth_format.json written (full-frame packed depth payload)")
    }

    private fun writePointCloudFormatIfNeeded() {
        if (pointcloudFormatWritten) return
        val json = """
            {
              "header": {
                "timestamp_ns": "int64",
                "point_count": "int32"
              },
              "floats_per_point": 4,
              "float_type": "float32",
              "point_layout": ["x", "y", "z", "confidence"],
              "endianness": "little"
            }
        """.trimIndent()
        writeZipEntryFromString("pointcloud_format.json", json)
        totalBytesWritten += json.toByteArray().size.toLong()
        pointcloudFormatWritten = true
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
                val entries = value.joinToString(",\n") { item ->
                    "$childIndent${toJsonValue(item, level + 1)}"
                }
                "[\n$entries\n$indent]"
            }
            else -> "\"${escapeJson(value.toString())}\""
        }
    }

    private fun escapeJson(raw: String): String {
        return raw
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}
