package open.fpvlabs.stera.ar_recorder

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import open.fpvlabs.stera.ar_recorder.coordination.FrameProcessingCoordinator
import open.fpvlabs.stera.ar_recorder.coordination.MetadataAssembler
import open.fpvlabs.stera.ar_recorder.coordination.PerformanceOptimizer
import open.fpvlabs.stera.ar_recorder.coordination.RecordingFinalizationCoordinator
import open.fpvlabs.stera.ar_recorder.coordination.RecordingFrameOrchestrator
import open.fpvlabs.stera.ar_recorder.coordination.RecordingHealthMonitor
import open.fpvlabs.stera.ar_recorder.coordination.RecordingLifecycleCoordinator
import open.fpvlabs.stera.ar_recorder.coordination.RecordingMetricsState
import open.fpvlabs.stera.ar_recorder.coordination.RecordingStateManager
import open.fpvlabs.stera.ar_recorder.coordination.RuntimeHealthManager
import open.fpvlabs.stera.ar_recorder.coordination.VideoEncodingCoordinator
import open.fpvlabs.stera.ar_recorder.data.DatasetWriter
import open.fpvlabs.stera.ar_recorder.data.DatasetWriterImpl
import open.fpvlabs.stera.ar_recorder.data.MCAPDatasetWriter
import open.fpvlabs.stera.ar_recorder.data.StorageManager
import open.fpvlabs.stera.ar_recorder.data.StorageManagerImpl
import open.fpvlabs.stera.ar_recorder.encoding.EglManager
import open.fpvlabs.stera.ar_recorder.encoding.EglManagerImpl
import open.fpvlabs.stera.ar_recorder.encoding.FrameSampler
import open.fpvlabs.stera.ar_recorder.encoding.FrameSamplerImpl
import open.fpvlabs.stera.ar_recorder.encoding.VideoEncoder
import open.fpvlabs.stera.ar_recorder.encoding.VideoEncoderImpl
import open.fpvlabs.stera.ar_recorder.metrics.PerformanceMonitor
import open.fpvlabs.stera.ar_recorder.metrics.PerformanceMonitorImpl
import open.fpvlabs.stera.ar_recorder.metrics.RecordingMetricsCollector
import open.fpvlabs.stera.ar_recorder.metrics.RecordingMetricsCollectorImpl
import open.fpvlabs.stera.ar_recorder.sensors.ImuCollector
import open.fpvlabs.stera.ar_recorder.sensors.ImuCollectorImpl
import open.fpvlabs.stera.ar_recorder.session.ArFrameProcessor
import open.fpvlabs.stera.ar_recorder.session.ArFrameProcessorImpl
import open.fpvlabs.stera.ar_recorder.session.ArSessionManager
import open.fpvlabs.stera.ar_recorder.session.ArSessionManagerImpl
import open.fpvlabs.stera.ar_recorder.session.FrameProcessingPipeline
import open.fpvlabs.stera.ar_recorder.session.SessionLifecycleManager
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Frame
import io.flutter.view.TextureRegistry
import java.io.File
import java.nio.ByteBuffer
import java.util.Date
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Main implementation of ArRecorder.
 * Orchestrates ARCore session, video encoding, IMU collection, and data writing.
 *
 * Delegates per-frame processing to [RecordingFrameOrchestrator],
 * runtime health monitoring to [RuntimeHealthManager],
 * metadata assembly to [MetadataAssembler],
 * and all mutable recording counters live in [RecordingMetricsState].
 */
class ArRecorderImpl(
    private val context: Context,
    private val textureRegistry: TextureRegistry
) : ArRecorder {

    private companion object {
        private const val SIZE_WARNING_THRESHOLD_BYTES = 2L * 1024L * 1024L * 1024L
        private const val VIDEO_FPS_FIXED = 15
        private const val VIDEO_BITRATE_30 = 10_000_000
        private const val VIDEO_BITRATE_1080P = 15_000_000
        private const val VIDEO_BITRATE_FALLBACK = 8_000_000
        private const val VIDEO_IFRAME_INTERVAL_SECONDS = 1
        private const val STORAGE_SAFETY_FACTOR = 0.8
        private const val STORAGE_PROJECTION_DURATION_SECONDS = 600L
        private const val DEPTH_BYTES_PER_SECOND_ESTIMATE = 2_500_000L
        private const val POINTCLOUD_BYTES_PER_SECOND_ESTIMATE = 250_000L
        private const val CSV_LOG_BYTES_PER_SECOND_ESTIMATE = 150_000L
        private const val POINTCLOUD_POOL_CAPACITY = 20
        private const val DEPTH_POOL_CAPACITY = 24

        /** Feature flag: when true, spatial data is written as MCAP; when false, uses legacy CSV+ZIP. */
        const val USE_MCAP_FORMAT = true
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Core sub-components ──────────────────────────────────────────────
    private val sessionManager: ArSessionManager = ArSessionManagerImpl(context)
    private val eglManager: EglManager = EglManagerImpl()
    private val frameProcessor: ArFrameProcessor = ArFrameProcessorImpl()
    private val imuCollector: ImuCollector = ImuCollectorImpl(context)
    private val datasetWriter: DatasetWriter = if (USE_MCAP_FORMAT) {
        MCAPDatasetWriter(
            context,
            Build.MODEL,
            "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
        )
    } else {
        DatasetWriterImpl(
            context,
            Build.MODEL,
            "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
        )
    }
    private val storageManager: StorageManager = StorageManagerImpl(
        safetyFactor = STORAGE_SAFETY_FACTOR,
        videoBitrateBitsPerSecond = VIDEO_BITRATE_1080P.toLong(),
        depthBytesPerSecondEstimate = DEPTH_BYTES_PER_SECOND_ESTIMATE,
        pointCloudBytesPerSecondEstimate = POINTCLOUD_BYTES_PER_SECOND_ESTIMATE,
        csvLogBytesPerSecondEstimate = CSV_LOG_BYTES_PER_SECOND_ESTIMATE
    )
    private val frameSampler: FrameSampler = FrameSamplerImpl(VIDEO_FPS_FIXED)
    private val metricsCollector: RecordingMetricsCollector = RecordingMetricsCollectorImpl()
    private val performanceMonitor: PerformanceMonitor = PerformanceMonitorImpl()
    private val videoEncoderManager: VideoEncoder = VideoEncoderImpl(
        logSystem = { message -> datasetWriter.logSystem(message) },
        recordError = { message, throwable -> recordError(message, throwable) },
        onEncodedSample = { metrics.encodedVideoFrameCount.incrementAndGet() }
    )
    private val videoEncodingCoordinator = VideoEncodingCoordinator(
        videoEncoder = videoEncoderManager,
        eglManager = eglManager,
        logSystem = { message -> datasetWriter.logSystem(message) },
        recordError = { message, throwable -> recordError(message, throwable) },
        onEncodedSampleSubmitted = { metrics.submittedToEncoderFrameCount.incrementAndGet() }
    )
    private val frameProcessingCoordinator = FrameProcessingCoordinator(
        frameSampler = frameSampler
    )
    private val recordingHealthMonitor = RecordingHealthMonitor(context)
    private val recordingLifecycleCoordinator = RecordingLifecycleCoordinator()
    private val recordingFinalizationCoordinator = RecordingFinalizationCoordinator()
    private val performanceOptimizer = PerformanceOptimizer()
    private val recordingStateManager = RecordingStateManager()
    private val frameProcessingPipeline = FrameProcessingPipeline()
    private val sessionLifecycleManager = SessionLifecycleManager()

    // ── Extracted state/orchestration classes ─────────────────────────────
    private val metrics = RecordingMetricsState()
    private val healthManager = RuntimeHealthManager(
        metrics = metrics,
        healthMonitor = recordingHealthMonitor,
        performanceOptimizer = performanceOptimizer,
        videoEncodingCoordinator = videoEncodingCoordinator,
        frameProcessingCoordinator = frameProcessingCoordinator,
        frameProcessor = frameProcessor,
        eglManager = eglManager,
        performanceMonitor = performanceMonitor,
        datasetWriter = datasetWriter,
        recordError = { message, throwable -> recordError(message, throwable) }
    )
    private val metadataAssembler = MetadataAssembler(metricsCollector)
    private val frameOrchestrator = RecordingFrameOrchestrator(
        metrics = metrics,
        healthManager = healthManager,
        frameProcessingPipeline = frameProcessingPipeline,
        frameProcessingCoordinator = frameProcessingCoordinator,
        eglManager = eglManager,
        frameProcessor = frameProcessor,
        frameSampler = frameSampler,
        imuCollector = imuCollector,
        datasetWriter = datasetWriter,
        sessionManager = sessionManager,
        recordError = { message, throwable -> recordError(message, throwable) }
    )

    // ── Thread management ────────────────────────────────────────────────
    private var frameThread: HandlerThread? = null
    private var frameHandler: Handler? = null
    private var writerThread: HandlerThread? = null
    private var writerHandler: Handler? = null

    // ── Core state ───────────────────────────────────────────────────────
    @Volatile
    private var currentState = ArRecordingState.UNINITIALIZED
    @Volatile
    private var isRecording = AtomicBoolean(false)
    @Volatile
    private var isPaused = AtomicBoolean(false)
    @Volatile
    private var shouldStopFrameLoop = AtomicBoolean(false)
    @Volatile
    private var releaseInProgress = AtomicBoolean(false)

    // ── Flutter preview ──────────────────────────────────────────────────
    private var flutterTexture: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurfaceTexture: SurfaceTexture? = null
    private var targetRgbLandscapeWidth: Int = 1280
    private var targetRgbLandscapeHeight: Int = 720
    private var previewWidth: Int = 1280
    private var previewHeight: Int = 720
    private var isPreviewBufferSizeSet = false
    private var previewResolutionDerived: Boolean = false

    // ── Camera / resolution ──────────────────────────────────────────────
    private var sensorWidth: Int = 1920
    private var sensorHeight: Int = 1080
    private var cameraResolution: String = "1920x1080"
    private var recordingResolution: String = "1280x720"
    private var isLowQualityMode: Boolean = false
    private var lowQualityReason: String? = null
    private val upscaleApplied: Boolean = false

    // ── Timing ───────────────────────────────────────────────────────────
    private var recordingStartTime: Long = 0
    private var pauseStartedAtMs: Long = 0
    private var totalPausedDurationMs: Long = 0
    private var lastTrackingState: String = "STOPPED"
    private var lastErrorMessage: String? = null

    // ── Video file reference ─────────────────────────────────────────────
    private var currentVideoFile: java.io.File? = null

    // ── Direct buffers for ARCore UV coordinate transformation ───────────
    private val uvCoordsInBuffer: java.nio.FloatBuffer = java.nio.ByteBuffer.allocateDirect(8 * 4)
        .order(java.nio.ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
            put(floatArrayOf(0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f))
            flip()
        }
    private val uvCoordsOutBuffer: java.nio.FloatBuffer = java.nio.ByteBuffer.allocateDirect(8 * 4)
        .order(java.nio.ByteOrder.nativeOrder())
        .asFloatBuffer()
    private val transformedUvs: FloatArray = FloatArray(8)

    // ═════════════════════════════════════════════════════════════════════
    //  Session Lifecycle
    // ═════════════════════════════════════════════════════════════════════

    override fun initializeSession(arguments: Any?): Map<String, Any?> {
        return try {
            if (currentState == ArRecordingState.INITIALIZING) {
                return createErrorResult("Already initializing")
            }
            if (currentState == ArRecordingState.READY) {
                return createSuccessResult(
                    depthSupported = sessionManager.isDepthSupported,
                    textureId = flutterTexture?.id()
                )
            }

            applyRgbTargets(RecordingConfig.fromMap(arguments))

            currentState = ArRecordingState.INITIALIZING
            println("📷 ArRecorderImpl: Initializing session...")

            flutterTexture = textureRegistry.createSurfaceTexture()
            val textureId = flutterTexture?.id()
            previewSurfaceTexture = flutterTexture?.surfaceTexture()

            if (!eglManager.initialize()) {
                currentState = ArRecordingState.ERROR
                return createErrorResult("Failed to initialize EGL context")
            }
            previewSurfaceTexture?.let { eglManager.setupPreviewSurface(it) }

            if (!imuCollector.initialize()) {
                println("⚠️ IMU collector initialization failed, continuing without IMU")
            }

            sessionManager.checkAvailability { availability ->
                if (availability.isSupported) {
                    (context as? Activity)?.let { activity ->
                        createSessionOnMainThread(activity)
                    } ?: run {
                        currentState = ArRecordingState.ERROR
                        println("❌ Context is not an Activity")
                    }
                } else {
                    currentState = ArRecordingState.ERROR
                    println("❌ ARCore not supported on this device: $availability")
                }
            }

            createSuccessResult(
                depthSupported = sessionManager.isDepthSupported,
                textureId = textureId,
                state = ArRecordingState.INITIALIZING.name
            )
        } catch (e: Exception) {
            currentState = ArRecordingState.ERROR
            println("❌ Failed to initialize session: ${e.message}")
            recordError("Failed to initialize session", e)
            e.printStackTrace()
            createErrorResult(e.message ?: "Unknown error")
        }
    }

    private fun createSessionOnMainThread(activity: Activity) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            performSessionCreation(activity)
            return
        }

        val latch = CountDownLatch(1)
        var failure: Exception? = null
        mainHandler.post {
            try {
                performSessionCreation(activity)
            } catch (e: Exception) {
                failure = e
            } finally {
                latch.countDown()
            }
        }
        latch.await()
        failure?.let { throw it }
    }

    /**
     * Session creation touches Activity-owned ARCore resources, so it stays on the main thread
     * even though recording work later moves onto the frame and writer threads.
     */
    private fun performSessionCreation(activity: Activity) {
        try {
            previewWidth = targetRgbLandscapeWidth
            previewHeight = targetRgbLandscapeHeight
            println("📱 Preview dimensions initial: ${previewWidth}x${previewHeight} (landscape)")

            sessionManager.createSession(activity)
            sessionManager.resume()
            eglManager.makeCurrent()
            eglManager.makeNothingCurrent()

            startFrameLoop()
            println("✅ Session initialization complete")
        } catch (e: Exception) {
            currentState = ArRecordingState.ERROR
            println("❌ Failed to create session: ${e.message}")
            recordError("Failed to create ARCore session", e)
            e.printStackTrace()
            throw e
        }
    }

    private fun startFrameLoop() {
        val handles = sessionLifecycleManager.startThreads { runFrameLoop() }
        frameThread = handles.frameThread
        frameHandler = handles.frameHandler
        writerThread = handles.writerThread
        writerHandler = handles.writerHandler
        healthManager.writerHandler = handles.writerHandler
        shouldStopFrameLoop.set(false)
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Frame Loop
    // ═════════════════════════════════════════════════════════════════════

    private fun runFrameLoop() {
        val session = sessionManager.session
        if (session == null) {
            println("❌ No ARCore session available")
            return
        }

        try {
            eglManager.makeCurrent()
            session.setCameraTextureName(eglManager.cameraTextureId)

            val cameraConfig = session.cameraConfig
            val imageSize = cameraConfig.imageSize
            sensorWidth = imageSize.width
            sensorHeight = imageSize.height
            applyResolutionPolicyFromCameraConfig()
            println("📷 Camera sensor dimensions: ${sensorWidth}x${sensorHeight}")
            println("📱 Preview dimensions: ${previewWidth}x${previewHeight}")
            println("🎥 Recording dimensions: ${metrics.configuredVideoWidth}x${metrics.configuredVideoHeight}")
            if (isLowQualityMode) {
                println("⚠️ Low quality mode enabled: $lowQualityReason")
            }

            while (!shouldStopFrameLoop.get()) {
                val displayRotation = (context as? Activity)?.windowManager?.defaultDisplay?.rotation ?: 0
                session.setDisplayGeometry(displayRotation, previewWidth, previewHeight)

                val frame = session.update()
                val camera = frame.camera

                val loopStartNs = SystemClock.elapsedRealtimeNanos()

                val isReady = sessionManager.updateTrackingState(camera.trackingState)
                val newTrackingState = sessionManager.getTrackingStateString(camera.trackingState)
                if (newTrackingState != lastTrackingState) {
                    datasetWriter.logTrackingStateTransition(lastTrackingState, newTrackingState, frame.timestamp)
                    if (lastTrackingState == ArTrackingState.TRACKING.name && newTrackingState != ArTrackingState.TRACKING.name) {
                        metrics.trackingLossEvents++
                    }
                    lastTrackingState = newTrackingState
                }

                if (isReady && currentState == ArRecordingState.INITIALIZING) {
                    currentState = ArRecordingState.READY
                    println("✅ ARCore session ready for recording")
                }

                renderFrame(frame, camera)

                if (isRecording.get()) {
                    frameOrchestrator.processFrame(
                        frame = frame,
                        camera = camera,
                        isPaused = isPaused.get(),
                        writerHandler = writerHandler,
                        uvCoordsInBuffer = uvCoordsInBuffer,
                        uvCoordsOutBuffer = uvCoordsOutBuffer,
                        transformedUvs = transformedUvs,
                        recordingStartTime = recordingStartTime,
                        estimateProjectionBytes = { elapsedMs -> estimateDatasetSizeProjectionBytes(elapsedMs) }
                    )
                }

                val loopDurationNs = SystemClock.elapsedRealtimeNanos() - loopStartNs
                metrics.renderLoopIterations++
                metrics.renderLoopTotalNs += loopDurationNs
            }
        } catch (e: Exception) {
            if (shouldStopFrameLoop.get() || releaseInProgress.get()) {
                return
            }
            println("❌ Frame loop error: ${e.message}")
            recordError("Frame loop error", e)
            e.printStackTrace()
            currentState = ArRecordingState.ERROR
        }
    }

    private fun renderFrame(frame: Frame, camera: com.google.ar.core.Camera) {
        try {
            uvCoordsInBuffer.rewind()
            uvCoordsOutBuffer.rewind()
            frame.transformDisplayUvCoords(uvCoordsInBuffer, uvCoordsOutBuffer)
            uvCoordsOutBuffer.rewind()
            uvCoordsOutBuffer.get(transformedUvs)

            previewSurfaceTexture?.let {
                if (!isPreviewBufferSizeSet) {
                    it.setDefaultBufferSize(previewWidth, previewHeight)
                    isPreviewBufferSizeSet = true
                }
                eglManager.renderCameraToPreview(previewWidth, previewHeight, transformedUvs)
            }
        } catch (e: Exception) {
            println("⚠️ Preview render error: ${e.message}")
            recordError("Preview render error", e)
            e.printStackTrace()
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Recording Lifecycle
    // ═════════════════════════════════════════════════════════════════════

    override fun startRecording(arguments: Any?): Map<String, Any?> {
        return try {
            if (!recordingStateManager.canStart(currentState)) {
                return createErrorResult("Session not ready. Current state: ${currentState.name}")
            }
            if (!sessionManager.isSessionReady) {
                return createErrorResult("Tracking not stable. Wait for TRACKING state.")
            }

            val recordingConfig = RecordingConfig.fromMap(arguments)
            applyRgbTargets(recordingConfig)

            println("📷 ArRecorderImpl: Starting recording...")
            currentState = ArRecordingState.RECORDING

            val storagePrecheck = verifyStorageHeadroomForLongRecording()
            if (!storagePrecheck.first) {
                currentState = ArRecordingState.READY
                return createErrorResult(storagePrecheck.second ?: "Insufficient storage headroom")
            }

            val sessionBaseDir = File(context.getExternalFilesDir(null), "ar_sessions")
            val sessionDir = datasetWriter.createSessionDirectory(sessionBaseDir)
                ?: return createErrorResult("Failed to create output directory")

            // Reset all metrics and health state
            val encodeBitrate =
                if (recordingConfig.rgbVideoHeight >= 1080) VIDEO_BITRATE_1080P else VIDEO_BITRATE_30
            metrics.reset(
                defaultVideoWidth = targetRgbLandscapeWidth,
                defaultVideoHeight = targetRgbLandscapeHeight,
                sensorWidth = sensorWidth,
                sensorHeight = sensorHeight,
                defaultBitrate = encodeBitrate,
                defaultFps = VIDEO_FPS_FIXED
            )
            healthManager.reset()
            cameraResolution = "${sensorWidth}x${sensorHeight}"
            recordingResolution = "${metrics.configuredVideoWidth}x${metrics.configuredVideoHeight}"
            isLowQualityMode = false
            lowQualityReason = null

            frameProcessor.prepareForRecording(
                pointCloudPoolCapacity = POINTCLOUD_POOL_CAPACITY,
                depthPoolCapacity = DEPTH_POOL_CAPACITY
            )
            recordingStartTime = System.currentTimeMillis()
            pauseStartedAtMs = 0L
            totalPausedDurationMs = 0L
            frameSampler.reset()
            if (!previewResolutionDerived) {
                applyResolutionPolicyFromCameraConfig()
            }

            if (!datasetWriter.initializeWriters()) {
                return createErrorResult("Failed to initialize writers")
            }

            val arcoreVersion = resolveArCoreVersion()
            datasetWriter.logSystem("Session start time: ${Date(recordingStartTime)}")
            datasetWriter.logSystem("Storage path: ${sessionDir.absolutePath}")
            datasetWriter.logSystem("Device model: ${Build.MODEL}")
            datasetWriter.logSystem("Android version: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            datasetWriter.logSystem("ARCore version: $arcoreVersion")
            datasetWriter.logSystem("Depth supported: ${sessionManager.isDepthSupported}")
            datasetWriter.logSystem("Camera resolution: $cameraResolution")
            datasetWriter.logSystem("Selected camera config: ${sessionManager.selectedCameraResolution}")
            datasetWriter.logSystem("Focus mode: ${sessionManager.selectedFocusMode}")
            datasetWriter.logSystem("Preview resolution: ${previewWidth}x${previewHeight}")
            datasetWriter.logSystem("Recording resolution: $recordingResolution")
            datasetWriter.logSystem("Low quality mode: $isLowQualityMode (${lowQualityReason ?: "none"})")
            datasetWriter.logSystem("Sensor sampling rates: accelerometer/gyroscope FASTEST")
            datasetWriter.logSystem("Pool capacities: depth=$DEPTH_POOL_CAPACITY pointcloud=$POINTCLOUD_POOL_CAPACITY")

            metrics.targetEncodeFps = VIDEO_FPS_FIXED
            metrics.encodeFrameIntervalNs = 1_000_000_000L / metrics.targetEncodeFps
            metrics.dynamicEncoderMode = "jpeg_to_mcap"

            frameSampler.configure(metrics.targetEncodeFps)

            datasetWriter.logSystem(
                "JPEG capture mode: width=${metrics.configuredVideoWidth} height=${metrics.configuredVideoHeight} fps=${metrics.targetEncodeFps} topic=/camera/rgb/compressed"
            )

            imuCollector.start()
            isRecording.set(true)
            isPaused.set(false)

            println("✅ Recording started: $sessionDir")

            createSuccessResult(
                state = ArRecordingState.RECORDING.name,
                outputDirectory = sessionDir.absolutePath,
                isLowQualityMode = isLowQualityMode,
                lowQualityReason = lowQualityReason,
                cameraResolution = cameraResolution,
                recordingResolution = recordingResolution
            )
        } catch (e: Exception) {
            currentState = ArRecordingState.ERROR
            recordError("Failed to start recording", e)
            createErrorResult("Failed to start recording: ${e.message}")
        }
    }

    override fun pauseRecording(): Map<String, Any?> {
        return try {
            if (!recordingStateManager.canPause(currentState)) {
                return createErrorResult("Not recording. Current state: ${currentState.name}")
            }
            val pauseResult = recordingLifecycleCoordinator.pauseRecording(System.currentTimeMillis())
            isPaused.set(pauseResult.isPaused)
            pauseStartedAtMs = pauseResult.pauseStartedAtMs
            currentState = pauseResult.nextState
            imuCollector.stop()
            datasetWriter.pauseWriters()
            createSuccessResult(
                state = ArRecordingState.PAUSED.name,
                outputDirectory = datasetWriter.getSessionDirectory(),
                isLowQualityMode = isLowQualityMode,
                lowQualityReason = lowQualityReason,
                cameraResolution = cameraResolution,
                recordingResolution = recordingResolution
            )
        } catch (e: Exception) {
            createErrorResult("Failed to pause recording: ${e.message}")
        }
    }

    override fun resumeRecording(): Map<String, Any?> {
        return try {
            if (!recordingStateManager.canResume(currentState)) {
                return createErrorResult("Not paused. Current state: ${currentState.name}")
            }
            val resumeResult = recordingLifecycleCoordinator.resumeRecording(
                nowMs = System.currentTimeMillis(),
                pauseStartedAtMs = pauseStartedAtMs,
                totalPausedDurationMs = totalPausedDurationMs
            )
            totalPausedDurationMs = resumeResult.totalPausedDurationMs
            pauseStartedAtMs = resumeResult.pauseStartedAtMs
            isPaused.set(resumeResult.isPaused)
            datasetWriter.resumeWriters()
            imuCollector.start()
            currentState = resumeResult.nextState
            createSuccessResult(
                state = ArRecordingState.RECORDING.name,
                outputDirectory = datasetWriter.getSessionDirectory(),
                isLowQualityMode = isLowQualityMode,
                lowQualityReason = lowQualityReason,
                cameraResolution = cameraResolution,
                recordingResolution = recordingResolution
            )
        } catch (e: Exception) {
            createErrorResult("Failed to resume recording: ${e.message}")
        }
    }

    override fun cancelRecording(): Map<String, Any?> {
        return try {
            if (!recordingStateManager.canCancel(currentState)) {
                return createErrorResult("Not recording. Current state: ${currentState.name}")
            }
            val cancelResult = recordingLifecycleCoordinator.cancelRecording()
            currentState = cancelResult.nextState
            isRecording.set(cancelResult.isRecording)
            isPaused.set(cancelResult.isPaused)
            pauseStartedAtMs = cancelResult.pauseStartedAtMs
            totalPausedDurationMs = cancelResult.totalPausedDurationMs

            imuCollector.stop()
            abortVideoEncoder()
            val deleted = datasetWriter.deleteSessionDirectory()
            if (!deleted) {
                currentState = ArRecordingState.ERROR
                return createErrorResult("Failed to discard recording files")
            }

            currentState = ArRecordingState.READY
            mapOf(
                "success" to true,
                "state" to ArRecordingState.READY.name,
                "cancelled" to true,
                "outputDirectory" to null,
                "previewWidth" to previewWidth,
                "previewHeight" to previewHeight,
                "error" to null
            )
        } catch (e: Exception) {
            currentState = ArRecordingState.ERROR
            createErrorResult("Failed to cancel recording: ${e.message}")
        }
    }

    override fun stopRecording(): Map<String, Any?> {
        return try {
            if (!recordingStateManager.canStop(currentState)) {
                return createErrorResult("Not recording. Current state: ${currentState.name}")
            }

            println("📷 ArRecorderImpl: Stopping recording...")
            currentState = ArRecordingState.STOPPING

            isRecording.set(false)
            if (isPaused.get()) {
                val pausedSince = pauseStartedAtMs
                if (pausedSince > 0L) {
                    totalPausedDurationMs += (System.currentTimeMillis() - pausedSince).coerceAtLeast(0L)
                }
            }
            isPaused.set(false)
            pauseStartedAtMs = 0L

            imuCollector.stop()

            // Process remaining IMU samples
            val remainingSamples = imuCollector.drainSamples()
            if (remainingSamples.isNotEmpty()) {
                remainingSamples.forEach { metrics.imuTimestampRange.record(it.timestampNs) }
                datasetWriter.writeImuSamples(remainingSamples)
            }

            // Compute core stats
            val coreStats = recordingFinalizationCoordinator.computeCoreStats(
                nowMs = System.currentTimeMillis(),
                recordingStartTimeMs = recordingStartTime,
                totalPausedDurationMs = totalPausedDurationMs,
                arcoreFrameCount = metrics.arcoreFrameCount.get(),
                encodedVideoFrameCount = metrics.encodedVideoFrameCount.get(),
                depthFrameCount = metrics.depthFrameCount.get(),
                pointCloudFrameCount = metrics.pointCloudFrameCount.get(),
                imuSampleCount = 0,
                videoFileSizeBytes = null
            )

            val resolutionFallback = metrics.actualVideoWidth != 0 && metrics.actualVideoHeight != 0 &&
                (metrics.actualVideoWidth != metrics.configuredVideoWidth || metrics.actualVideoHeight != metrics.configuredVideoHeight)
            if (resolutionFallback) {
                datasetWriter.logSystem(
                    "FALLBACK: encoder produced ${metrics.actualVideoWidth}x${metrics.actualVideoHeight} instead of ${metrics.configuredVideoWidth}x${metrics.configuredVideoHeight}"
                )
            }

            val encoderQueueDepth = metrics.encoderQueueDepth()
            if (encoderQueueDepth > metrics.maxEncoderQueueDepth) {
                metrics.maxEncoderQueueDepth = encoderQueueDepth
            }

            // Drain writer thread
            val writerLatch = CountDownLatch(1)
            if (writerHandler != null) {
                writerHandler?.post { writerLatch.countDown() }
                writerLatch.await()
            } else {
                println("⚠️ Writer thread not available, skipping drain")
            }

            datasetWriter.captureFreeStorageAfterSnapshot()

            val stats = datasetWriter.getRecordingStats()
            val totalBytesWritten = (stats["totalBytesWritten"] as? Long) ?: 0L
            val imuSampleCount = (stats["imuSampleCount"] as? Int ?: 0)
            val appVersion = resolveAppVersion()
            val appBuild = resolveAppBuild()

            // Assemble metadata via MetadataAssembler
            val finalizationResult = metadataAssembler.assemble(
                MetadataAssembler.FinalizationInput(
                    metrics = metrics,
                    health = healthManager,
                    coreStats = coreStats,
                    sessionManager = sessionManager,
                    frameProcessor = frameProcessor,
                    imuCollector = imuCollector,
                    datasetWriter = datasetWriter,
                    eglManager = eglManager,
                    recordingResolution = recordingResolution,
                    cameraResolution = cameraResolution,
                    previewWidth = previewWidth,
                    previewHeight = previewHeight,
                    isLowQualityMode = isLowQualityMode,
                    lowQualityReason = lowQualityReason,
                    upscaleApplied = upscaleApplied,
                    arcoreVersion = resolveArCoreVersion(),
                    appVersion = appVersion,
                    appBuild = appBuild,
                    imuSampleCount = imuSampleCount,
                    totalBytesWritten = totalBytesWritten,
                    estimatedDatasetSizeBytes = estimateDatasetSizeProjectionBytes(coreStats.durationMs),
                    sizeWarningThresholdBytes = SIZE_WARNING_THRESHOLD_BYTES,
                    recordingStartTime = recordingStartTime
                )
            )

            datasetWriter.writeMetadata(finalizationResult.metadata)

            // Log session end info
            datasetWriter.logSystem("Session end time: ${Date()}")
            datasetWriter.logSystem("Errors encountered: ${metrics.totalErrorsEncountered}")
            datasetWriter.logSystem("Tracking loss events: ${metrics.trackingLossEvents}")
            datasetWriter.logSystem("Free storage before: ${datasetWriter.getFreeStorageBeforeBytes()} bytes")
            datasetWriter.logSystem("Free storage after: ${datasetWriter.getFreeStorageAfterBytes()} bytes")
            datasetWriter.logSystem("Total bytes written: $totalBytesWritten bytes")
            if (totalBytesWritten > SIZE_WARNING_THRESHOLD_BYTES) {
                datasetWriter.logSystem(
                    "WARN: session size exceeded threshold. bytes=$totalBytesWritten threshold=$SIZE_WARNING_THRESHOLD_BYTES"
                )
            }

            val durationSeconds = coreStats.durationSeconds
            val imuFps = if (durationSeconds > 0.0) imuSampleCount.toDouble() / durationSeconds else 0.0

            val sessionSummary = recordingFinalizationCoordinator.buildSessionSummary(
                durationSeconds = durationSeconds,
                arcoreFps = coreStats.arcoreFps,
                encodedVideoFps = coreStats.encodedVideoFps,
                depthFps = coreStats.depthFps,
                imuFps = imuFps,
                cameraResolution = cameraResolution,
                recordingResolution = recordingResolution,
                isLowQualityMode = isLowQualityMode,
                lowQualityReason = lowQualityReason,
                maxEncoderQueueDepth = metrics.maxEncoderQueueDepth,
                encoderBackpressureDetected = metrics.encoderBackpressureDetected
            )
            datasetWriter.writeSessionSummary(sessionSummary)

            val (zipSuccess, zipPath, zipError) = datasetWriter.createSpatialDataZip()

            datasetWriter.finalize()
            if (!zipSuccess) {
                println("⚠️ Failed to create spatial_data.zip: $zipError")
            } else {
                println("✅ spatial_data.zip created: $zipPath")
            }

            val outputDir = datasetWriter.getSessionDirectory()
            currentState = ArRecordingState.READY

            println("✅ Recording stopped: $outputDir")

            mapOf(
                "success" to true,
                "state" to ArRecordingState.READY.name,
                "depthSupported" to sessionManager.isDepthSupported,
                "outputDirectory" to outputDir,
                "sessionPath" to outputDir,
                "durationSeconds" to durationSeconds,
                "framesRecorded" to metrics.frameCount,
                "imuSamples" to (stats["imuSampleCount"] ?: 0),
                "galleryUri" to null,
                "isLowQualityMode" to isLowQualityMode,
                "lowQualityReason" to lowQualityReason,
                "cameraResolution" to cameraResolution,
                "recordingResolution" to recordingResolution,
                "previewWidth" to previewWidth,
                "previewHeight" to previewHeight,
                "upscaleApplied" to upscaleApplied,
                "error" to null
            )
        } catch (e: Exception) {
            currentState = ArRecordingState.ERROR
            println("❌ Failed to stop recording: ${e.message}")
            recordError("Failed to stop recording", e)
            e.printStackTrace()
            createErrorResult(e.message ?: "Unknown error")
        }
    }

    override fun getRecordingState(): Map<String, Any?> {
        val duration = if (isRecording.get()) {
            val activePausedMs = if (isPaused.get() && pauseStartedAtMs > 0L) {
                (System.currentTimeMillis() - pauseStartedAtMs).coerceAtLeast(0L)
            } else 0L
            (System.currentTimeMillis() - recordingStartTime - totalPausedDurationMs - activePausedMs).coerceAtLeast(0L)
        } else null

        return mapOf(
            "state" to currentState.name,
            "trackingState" to lastTrackingState,
            "isRecording" to isRecording.get(),
            "isPaused" to isPaused.get(),
            "depthSupported" to sessionManager.isDepthSupported,
            "recordingDuration" to duration,
            "frameCount" to if (isRecording.get() || currentState == ArRecordingState.PAUSED) metrics.frameCount else null,
            "textureId" to flutterTexture?.id(),
            "cameraResolution" to cameraResolution,
            "recordingResolution" to recordingResolution,
            "previewWidth" to previewWidth,
            "previewHeight" to previewHeight,
            "isLowQualityMode" to isLowQualityMode,
            "lowQualityReason" to lowQualityReason,
            "upscaleApplied" to upscaleApplied,
            "error" to lastErrorMessage
        )
    }

    override fun checkArAvailability(): Map<String, Any?> {
        val availability = ArCoreApk.getInstance().checkAvailability(context)
        return mapOf("supported" to availability.isSupported)
    }

    override fun disposeSession() {
        println("📷 ArRecorderImpl: Disposing session...")

        releaseInProgress.set(true)
        if (isRecording.get()) {
            stopRecording()
        }

        currentState = ArRecordingState.DISPOSED
        shouldStopFrameLoop.set(true)

        sessionLifecycleManager.stopThreads(frameThread, writerThread)
        frameThread = null
        frameHandler = null
        writerThread = null
        writerHandler = null

        imuCollector.release()
        datasetWriter.release()
        sessionManager.release()
        eglManager.release()

        sessionLifecycleManager.releaseFlutterPreviewTexture(flutterTexture) {
            previewSurfaceTexture = it
        }
        flutterTexture = null
        isPreviewBufferSizeSet = false
        currentVideoFile = null
        releaseInProgress.set(false)

        println("✅ Session disposed")
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Video Encoder Wrappers
    // ═════════════════════════════════════════════════════════════════════

    private fun applyResolutionPolicyFromCameraConfig() {
        val result = sessionLifecycleManager.applyResolutionPolicyFromCameraConfig(
            sensorWidth = sensorWidth,
            sensorHeight = sensorHeight,
            videoWidth = targetRgbLandscapeWidth,
            videoHeight = targetRgbLandscapeHeight
        )
        metrics.configuredVideoWidth = result.configuredVideoWidth
        metrics.configuredVideoHeight = result.configuredVideoHeight
        previewWidth = result.previewWidth
        previewHeight = result.previewHeight
        cameraResolution = result.cameraResolution
        recordingResolution = result.recordingResolution
        isLowQualityMode = result.isLowQualityMode
        lowQualityReason = result.lowQualityReason
        previewResolutionDerived = result.previewResolutionDerived
        isPreviewBufferSizeSet = false
    }

    private fun setupVideoEncoder(outputFile: File): Boolean {
        val result = videoEncodingCoordinator.setupVideoEncoder(
            outputFile = outputFile,
            configuredVideoWidth = metrics.configuredVideoWidth,
            configuredVideoHeight = metrics.configuredVideoHeight,
            targetEncodeFps = metrics.targetEncodeFps,
            targetVideoBitrate = metrics.targetVideoBitrate,
            fallbackBitrate = VIDEO_BITRATE_FALLBACK,
            iFrameIntervalSeconds = VIDEO_IFRAME_INTERVAL_SECONDS
        )
        if (!result.success) return false
        metrics.activeVideoBitrate = result.activeVideoBitrate
        metrics.targetVideoBitrate = result.targetVideoBitrate
        metrics.actualVideoWidth = result.actualVideoWidth
        metrics.actualVideoHeight = result.actualVideoHeight
        metrics.encoderSurfaceReady = result.encoderSurfaceReady

        // Propagate encoder fallback: fps, resolution, and frame interval
        if (result.chosenFps != metrics.targetEncodeFps) {
            metrics.targetEncodeFps = result.chosenFps
            metrics.encodeFrameIntervalNs = 1_000_000_000L / result.chosenFps
        }
        if (result.chosenWidth != metrics.configuredVideoWidth || result.chosenHeight != metrics.configuredVideoHeight) {
            metrics.configuredVideoWidth = result.chosenWidth
            metrics.configuredVideoHeight = result.chosenHeight
            recordingResolution = "${result.chosenWidth}x${result.chosenHeight}"
            isLowQualityMode = true
            lowQualityReason = "encoder_fallback_resolution"
        } else if (result.chosenFps != VIDEO_FPS_FIXED) {
            isLowQualityMode = true
            lowQualityReason = "encoder_fallback_fps"
        }
        return true
    }

    private fun finalizeVideoEncoder() {
        val result = videoEncodingCoordinator.finalizeVideoEncoder(
            configuredVideoWidth = metrics.configuredVideoWidth,
            configuredVideoHeight = metrics.configuredVideoHeight,
            targetEncodeFps = metrics.targetEncodeFps
        )
        metrics.actualVideoWidth = result.actualVideoWidth
        metrics.actualVideoHeight = result.actualVideoHeight
    }

    private fun releaseVideoEncoder() {
        videoEncodingCoordinator.releaseVideoEncoder()
        metrics.encoderSurfaceReady = false
    }

    private fun abortVideoEncoder() {
        releaseVideoEncoder()
        metrics.actualVideoWidth = 0
        metrics.actualVideoHeight = 0
        currentVideoFile = null
    }

    // ═════════════════════════════════════════════════════════════════════
    //  Utilities
    // ═════════════════════════════════════════════════════════════════════

    private fun recordError(message: String, throwable: Throwable? = null) {
        metrics.totalErrorsEncountered++
        datasetWriter.logError(message, throwable)
    }

    private fun resolveArCoreVersion(): String {
        return try {
            val packageName = "com.google.ar.core"
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(packageName, 0)
            }
            packageInfo.versionName ?: "unknown"
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun resolveAppVersion(): String {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(context.packageName, 0)
            }
            packageInfo.versionName ?: "unknown"
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun resolveAppBuild(): String {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(context.packageName, 0)
            }
            packageInfo.longVersionCode.toString()
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun estimateDatasetSizeProjectionBytes(durationMs: Long): Long {
        val elapsedMs = durationMs.coerceAtLeast(1L)
        val stats = datasetWriter.getRecordingStats()
        val bytesWritten = (stats["totalBytesWritten"] as? Long ?: 0L).coerceAtLeast(0L)
        val bytesPerMs = bytesWritten.toDouble() / elapsedMs.toDouble()
        val projectedForOneMinute = bytesPerMs * 60_000.0
        return projectedForOneMinute.toLong()
    }

    private fun applyRgbTargets(cfg: RecordingConfig) {
        targetRgbLandscapeWidth = cfg.rgbLandscapeWidth
        targetRgbLandscapeHeight = cfg.rgbLandscapeHeight
        previewWidth = cfg.rgbLandscapeWidth
        previewHeight = cfg.rgbLandscapeHeight
        isPreviewBufferSizeSet = false
    }

    private fun verifyStorageHeadroomForLongRecording(): Pair<Boolean, String?> {
        val baseDir = File(context.getExternalFilesDir(null), "ar_sessions")
        baseDir.mkdirs()
        val estimatedBytes = storageManager.estimateDatasetSize(
            durationSeconds = STORAGE_PROJECTION_DURATION_SECONDS,
            includeDepth = sessionManager.isDepthSupported
        )
        val result = storageManager.verifyHeadroom(
            baseDir = baseDir,
            durationSeconds = STORAGE_PROJECTION_DURATION_SECONDS,
            includeDepth = sessionManager.isDepthSupported
        )
        if (!result.first) {
            println("❌ ${result.second}")
            return result
        }
        val availableBytes = baseDir.usableSpace
        val thresholdBytes = (availableBytes.toDouble() * STORAGE_SAFETY_FACTOR).toLong()
        println(
            "✅ Storage precheck passed. estimated=${estimatedBytes} available=${availableBytes} threshold80=${thresholdBytes}"
        )
        return Pair(true, null)
    }

    private fun createSuccessResult(
        state: String = ArRecordingState.READY.name,
        depthSupported: Boolean = sessionManager.isDepthSupported,
        textureId: Long? = null,
        outputDirectory: String? = null,
        galleryUri: String? = null,
        isLowQualityMode: Boolean = false,
        lowQualityReason: String? = null,
        cameraResolution: String? = null,
        recordingResolution: String? = null,
        upscaleApplied: Boolean = false
    ): Map<String, Any?> {
        lastErrorMessage = null
        return mapOf(
            "success" to true,
            "state" to state,
            "depthSupported" to depthSupported,
            "textureId" to textureId,
            "outputDirectory" to outputDirectory,
            "galleryUri" to galleryUri,
            "isLowQualityMode" to isLowQualityMode,
            "lowQualityReason" to lowQualityReason,
            "cameraResolution" to cameraResolution,
            "recordingResolution" to recordingResolution,
            "previewWidth" to previewWidth,
            "previewHeight" to previewHeight,
            "upscaleApplied" to upscaleApplied,
            "error" to null
        )
    }

    private fun createErrorResult(errorMessage: String): Map<String, Any?> {
        lastErrorMessage = errorMessage
        return mapOf(
            "success" to false,
            "state" to currentState.name,
            "depthSupported" to sessionManager.isDepthSupported,
            "textureId" to flutterTexture?.id(),
            "outputDirectory" to null,
            "isLowQualityMode" to isLowQualityMode,
            "lowQualityReason" to lowQualityReason,
            "cameraResolution" to cameraResolution,
            "recordingResolution" to recordingResolution,
            "previewWidth" to previewWidth,
            "previewHeight" to previewHeight,
            "upscaleApplied" to upscaleApplied,
            "error" to errorMessage
        )
    }
}
