package open.fpvlabs.stera.ar_recorder.coordination

import android.os.Handler
import android.os.SystemClock
import open.fpvlabs.stera.ar_recorder.data.DatasetWriter
import open.fpvlabs.stera.ar_recorder.encoding.EglManager
import open.fpvlabs.stera.ar_recorder.encoding.FrameSampler
import open.fpvlabs.stera.ar_recorder.sensors.ImuCollector
import open.fpvlabs.stera.ar_recorder.session.ArFrameProcessor
import open.fpvlabs.stera.ar_recorder.session.ArSessionManager
import open.fpvlabs.stera.ar_recorder.session.FrameProcessingPipeline
import com.google.ar.core.Frame
import java.nio.FloatBuffer

/**
 * Orchestrates per-frame recording logic that was previously inline in
 * [ArRecorderImpl.processRecordingFrame].
 *
 * Each call to [processFrame] handles:
 * - ARCore cadence estimation
 * - Tracking transition evaluation
 * - Intrinsics extraction (first frame)
 * - Encoder backpressure gate
 * - RGB video encoding
 * - Pose extraction and writing
 * - Point cloud extraction and writing
 * - Depth extraction and writing
 * - Frame log row writing
 * - IMU sample draining
 * - Post-frame health checks and maintenance
 */
class RecordingFrameOrchestrator(
    private val metrics: RecordingMetricsState,
    private val healthManager: RuntimeHealthManager,
    private val frameProcessingPipeline: FrameProcessingPipeline,
    private val frameProcessingCoordinator: FrameProcessingCoordinator,
    private val eglManager: EglManager,
    private val frameProcessor: ArFrameProcessor,
    private val frameSampler: FrameSampler,
    private val imuCollector: ImuCollector,
    private val datasetWriter: DatasetWriter,
    private val sessionManager: ArSessionManager,
    private val recordError: (String, Throwable?) -> Unit
) {
    companion object {
        private const val JPEG_QUALITY = 80
    }

    /**
     * Processes a single recording frame. Called from the frame loop for every
     * ARCore frame while recording is active.
     *
     * @param frame the ARCore frame
     * @param camera the AR camera
     * @param isPaused whether recording is paused
     * @param writerHandler handler for async write operations (nullable)
     * @param uvCoordsInBuffer UV input buffer for encoding
     * @param uvCoordsOutBuffer UV output buffer for encoding
     * @param transformedUvs UV float array for encoding
     * @param recordingStartTime recording start timestamp in millis
     * @param estimateProjectionBytes function to estimate projected dataset bytes
     */
    fun processFrame(
        frame: Frame,
        camera: com.google.ar.core.Camera,
        isPaused: Boolean,
        writerHandler: Handler?,
        uvCoordsInBuffer: FloatBuffer,
        uvCoordsOutBuffer: FloatBuffer,
        transformedUvs: FloatArray,
        recordingStartTime: Long,
        estimateProjectionBytes: (Long) -> Long
    ) {
        if (!frameProcessingPipeline.shouldProcess(isPaused, frame)) {
            return
        }

        val timestamp = frame.timestamp
        metrics.arcoreFrameCount.incrementAndGet()
        val globalFrameIndex = ++metrics.globalArFrameIndex
        metrics.lastObservedArcoreTimestampNs = timestamp
        updateArcoreCadenceEstimate(timestamp)

        val trackingState = frameProcessor.extractTrackingState(camera)
        val trackingTransition = frameProcessingPipeline.evaluateTrackingTransition(
            timestampNs = timestamp,
            camera = camera,
            trackingPausedAtNs = metrics.trackingPausedAtNs,
            trackingPauseCount = metrics.trackingPauseCount,
            trackingPauseTotalOffsetNs = metrics.trackingPauseTotalOffsetNs,
            wasTrackingInPreviousFrame = metrics.wasTrackingInPreviousFrame,
            depthCadenceResetCount = metrics.depthCadenceResetCount,
            onTrackingPauseOffset = { offsetNs -> frameSampler.recordTrackingPauseOffset(offsetNs) }
        )
        metrics.trackingPausedAtNs = trackingTransition.trackingPausedAtNs
        metrics.trackingPauseCount = trackingTransition.trackingPauseCount
        metrics.trackingPauseTotalOffsetNs = trackingTransition.trackingPauseTotalOffsetNs
        metrics.wasTrackingInPreviousFrame = trackingTransition.wasTrackingInPreviousFrame
        metrics.depthCadenceResetCount = trackingTransition.depthCadenceResetCount
        val isTracking = metrics.wasTrackingInPreviousFrame

        var depthAvailable = false
        var pointCloudAvailable = false
        var encoded = false

        val pose = if (isTracking) frameProcessor.extractPose(camera) else null
        val shouldSample = pose != null && frameSampler.shouldEncodeFrame(timestamp)

        if (isTracking && !shouldSample) {
            metrics.rgbSamplingSkippedCount++
        }

        if (shouldSample && pose != null) {
            // Extract intrinsics
            val intrinsics = frameProcessor.extractIntrinsics(camera)
            writerHandler?.post {
                datasetWriter.writeIntrinsics(timestamp, intrinsics)
            }

            // Write pose (extracted above for the distance gate)
            metrics.poseFrameCount.incrementAndGet()
            metrics.poseTimestampRange.record(timestamp)
            writerHandler?.post {
                datasetWriter.writePoseRow(timestamp, pose, trackingState)
            }

            // Extract point cloud
            pointCloudAvailable = processPointCloud(frame, timestamp, globalFrameIndex, writerHandler)

            // Extract depth
            val depthDims = processDepth(frame, timestamp, globalFrameIndex, isTracking, writerHandler)
            depthAvailable = depthDims != null

            // Write depth intrinsics using dimensions from the already-extracted depth frame
            if (depthDims != null) {
                val depthIntrinsics = frameProcessor.extractDepthIntrinsics(camera, depthDims.first, depthDims.second)
                if (depthIntrinsics != null) {
                    writerHandler?.post {
                        datasetWriter.writeDepthIntrinsics(timestamp, depthIntrinsics)
                    }
                }
            }

            // JPEG capture
            val jpegData = eglManager.renderCameraToJpeg(
                viewportWidth = metrics.configuredVideoWidth,
                viewportHeight = metrics.configuredVideoHeight,
                uvCoords = transformedUvs,
                jpegQuality = JPEG_QUALITY
            )
            if (jpegData != null) {
                encoded = true
                metrics.rgbTimestampRange.record(timestamp)
                metrics.addTimestampWithCap(metrics.rgbFrameTimestamps, timestamp)
                metrics.rgbEncodedFrameIndices.add(globalFrameIndex)
                metrics.encodedVideoFrameCount.incrementAndGet()
                metrics.submittedToEncoderFrameCount.incrementAndGet()
                writerHandler?.post {
                    datasetWriter.writeCompressedRgbFrame(timestamp, jpegData)
                }
            } else {
                metrics.rgbEncoderFailureCount++
                metrics.rgbEncoderFailureFrameIndices.add(globalFrameIndex)
                metrics.droppedFrameCount.incrementAndGet()
            }
        }

        // Write frame log
        writerHandler?.post {
            datasetWriter.writeFrameLogRow(
                frameIndex = metrics.frameCount,
                globalArFrameIndex = globalFrameIndex,
                arcoreTimestampNs = timestamp,
                trackingState = trackingState,
                encoded = encoded,
                depthAvailable = depthAvailable,
                pointCloudAvailable = pointCloudAvailable
            )
        } ?: datasetWriter.writeFrameLogRow(
            frameIndex = metrics.frameCount,
            globalArFrameIndex = globalFrameIndex,
            arcoreTimestampNs = timestamp,
            trackingState = trackingState,
            encoded = encoded,
            depthAvailable = depthAvailable,
            pointCloudAvailable = pointCloudAvailable
        )

        // Drain IMU samples
        val imuSamples = imuCollector.drainSamples()
        if (imuSamples.isNotEmpty()) {
            imuSamples.forEach { metrics.imuTimestampRange.record(it.timestampNs) }
            writerHandler?.post {
                datasetWriter.writeImuSamples(imuSamples)
            }
        }

        writerHandler?.post {
            // Write device metrics per-frame (~15Hz) using cached values
            healthManager.writeDeviceMetricsForFrame(timestamp)
            datasetWriter.flushRealtimeData(timestamp)
        }

        // Refresh device metrics cache (~every 500ms) on the frame processing thread
        healthManager.maybeRefreshDeviceMetricsCache()

        healthManager.verifyResourceReleaseParity()
        healthManager.maybeSampleRuntimeHealth()
        healthManager.maybeRunPeriodicMaintenance()
        syncSamplerStats()
        healthManager.maybeLogSizeProjection(recordingStartTime, estimateProjectionBytes)

        metrics.frameCount++
    }

    // ── Internal helpers ─────────────────────────────────────────────────

    private fun processPointCloud(
        frame: Frame,
        timestamp: Long,
        globalFrameIndex: Int,
        writerHandler: Handler?
    ): Boolean {
        val pointCloudPoolAvailable = frameProcessor.getPointCloudPoolAvailableCount()
        if (pointCloudPoolAvailable == 0) {
            metrics.pointCloudSoftSkipCount++
            metrics.pointcloudDroppedFrameIndices.add(globalFrameIndex)
            return false
        } else {
            val pointCloudData = frameProcessor.extractPointCloudFrame(frame, timestamp)
            if (pointCloudData != null) {
                metrics.pointCloudTimestampRange.record(timestamp)
                metrics.pointcloudFrameIndices.add(globalFrameIndex)
                metrics.pointCloudFrameCount.incrementAndGet()
            } else {
                metrics.pointcloudDroppedFrameIndices.add(globalFrameIndex)
            }
            if (writerHandler != null) {
                writerHandler.post {
                    datasetWriter.writePointCloud(timestamp, pointCloudData)
                }
            } else {
                pointCloudData?.release?.invoke()
            }
            return pointCloudData != null
        }
    }

    private fun processDepth(
        frame: Frame,
        timestamp: Long,
        globalFrameIndex: Int,
        isTracking: Boolean,
        writerHandler: Handler?
    ): Pair<Int, Int>? {
        if (!sessionManager.isDepthSupported) return null

        if (!isTracking) {
            metrics.trackingPauseDepthSkipCount++
            metrics.depthDroppedFrameIndices.add(globalFrameIndex)
            return null
        }

        metrics.addTimestampWithCap(metrics.depthAssociationCandidateRgbTimestamps, timestamp)
        metrics.depthAttemptCount++
        val depthStartNs = SystemClock.elapsedRealtimeNanos()
        val depthFrame = frameProcessor.extractDepthImage(frame)
        val depthLatencyNs = SystemClock.elapsedRealtimeNanos() - depthStartNs
        metrics.depthAcquisitionSamples++
        metrics.depthAcquisitionTotalLatencyNs += depthLatencyNs
        if (depthLatencyNs > metrics.depthAcquisitionMaxLatencyNs) {
            metrics.depthAcquisitionMaxLatencyNs = depthLatencyNs
        }

        if (depthFrame != null) {
            val depthWidth = depthFrame.width
            val depthHeight = depthFrame.height
            metrics.depthSuccessCount++
            metrics.depthFrameIndices.add(globalFrameIndex)
            if (writerHandler != null) {
                writerHandler.post {
                    val depthWritten = datasetWriter.writeDepthFrame(timestamp = timestamp, frameData = depthFrame)
                    if (!depthWritten) {
                        metrics.skippedDepthFrameCount.incrementAndGet()
                    }
                }
            } else {
                depthFrame.release()
            }
            metrics.depthTimestampRange.record(timestamp)
            metrics.addTimestampWithCap(metrics.depthFrameTimestamps, timestamp)
            metrics.depthFrameCount.incrementAndGet()
            return Pair(depthWidth, depthHeight)
        } else {
            metrics.skippedDepthFrameCount.incrementAndGet()
            metrics.depthDroppedFrameIndices.add(globalFrameIndex)
            return null
        }
    }

    private fun syncSamplerStats() {
        val stats = frameProcessingCoordinator.syncSamplerStats()
        if (stats.totalExpectedFrameCount != 0L) {
            metrics.totalExpectedFrameCount = stats.totalExpectedFrameCount
        }
        if (stats.deterministicFrameIndex != 0L) {
            metrics.deterministicFrameIndex = stats.deterministicFrameIndex
        }
        if (stats.sessionStartTimestampNs != Long.MIN_VALUE) {
            metrics.sessionStartTimestampNs = stats.sessionStartTimestampNs
        }
    }

    private fun updateArcoreCadenceEstimate(arcoreTimestampNs: Long) {
        val stats = frameProcessingCoordinator.updateArcoreCadenceEstimate(
            arcoreTimestampNs = arcoreTimestampNs,
            lastArcoreTimestampNsForEstimate = metrics.lastArcoreTimestampNsForEstimate,
            arcoreCadenceSamples = metrics.arcoreCadenceSamples,
            arcoreCadenceMeanIntervalNs = metrics.arcoreCadenceMeanIntervalNs,
            arcoreCadenceM2IntervalNs = metrics.arcoreCadenceM2IntervalNs
        )
        metrics.arcoreCadenceSamples = stats.samples
        metrics.arcoreCadenceMeanIntervalNs = stats.meanIntervalNs
        metrics.arcoreCadenceM2IntervalNs = stats.m2IntervalNs
        metrics.lastArcoreTimestampNsForEstimate = stats.lastArcoreTimestampNsForEstimate
    }
}
