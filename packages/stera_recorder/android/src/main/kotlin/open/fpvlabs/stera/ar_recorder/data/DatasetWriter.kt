package open.fpvlabs.stera.ar_recorder.data

import open.fpvlabs.stera.ar_recorder.sensors.ImuSample
import open.fpvlabs.stera.ar_recorder.session.DepthFrameData
import open.fpvlabs.stera.ar_recorder.session.PointCloudFrameData
import java.io.File

interface DatasetWriter {
    fun createSessionDirectory(baseDir: File? = null): File?
    fun pauseWriters()
    fun resumeWriters()
    fun deleteSessionDirectory(): Boolean
    fun initializeWriters(): Boolean
    fun logSystem(message: String)
    fun logError(message: String, throwable: Throwable? = null)
    fun writePoseRow(timestamp: Long, pose: FloatArray, trackingState: String)
    fun writeImuSamples(samples: List<ImuSample>)
    fun writeFrameLogRow(
        frameIndex: Int,
        globalArFrameIndex: Int,
        arcoreTimestampNs: Long,
        trackingState: String,
        encoded: Boolean,
        depthAvailable: Boolean,
        pointCloudAvailable: Boolean
    )
    fun writeDeviceMetrics(
        timestampNs: Long,
        batteryLevel: Float,
        batteryState: Int,
        batteryStateStr: String,
        cpuUsage: Float,
        memoryUsedMb: Double,
        memoryAvailableMb: Double,
        thermalState: Int,
        thermalStateStr: String
    )
    fun logTrackingStateTransition(previousState: String, nextState: String, timestampNs: Long)
    fun writePointCloud(timestamp: Long, frameData: PointCloudFrameData?)
    fun writeCompressedRgbFrame(timestamp: Long, jpegData: ByteArray)
    fun writeDepthFrame(timestamp: Long, frameData: DepthFrameData?): Boolean
    fun writeIntrinsics(timestampNs: Long, intrinsics: Map<String, Any>)
    fun writeDepthIntrinsics(timestampNs: Long, intrinsics: Map<String, Any>)
    fun writeMetadata(metadata: Map<String, Any?>)
    fun writeSessionSummary(summaryText: String)
    fun writeFrameDropLog(dropLog: Map<String, Any?>): String?
    fun addVideoBytesWritten(videoBytes: Long)
    fun getVideoOutputPath(): String?
    fun getSessionDirectory(): String?
    fun getRecordingStats(): Map<String, Any>
    fun getFreeStorageBeforeBytes(): Long
    fun getFreeStorageAfterBytes(): Long
    fun getWriterAverageLatencyMs(): Double
    fun flushRealtimeData(timestampNs: Long)
    fun captureFreeStorageAfterSnapshot()
    fun createSpatialDataZip(): Triple<Boolean, String?, String?>
    fun finalize()
    fun release()
}
