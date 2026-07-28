import ARKit
import CoreMotion
import Flutter
import Foundation
import UIKit

/// Main implementation of ArRecorder for iOS.
/// Orchestrates ARKit session, video encoding, IMU collection, and data writing.
/// Uses ARSessionDelegate push model instead of Android's polling frame loop.
class ArRecorderImpl: NSObject, ArRecorder, ArSessionManagerDelegate {

    private static let sizeWarningThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024
    private static let videoFpsFixed = 15
    private static let videoBitrate720p = 10_000_000
    private static let videoBitrate1080p = 15_000_000
    private static let videoBitrate4k = 50_000_000
    private static let storageSafetyFactor = 0.8
    private static let storageProjectionDurationSeconds: Int64 = 600
    private static let depthBytesPerSecondEstimate: Int64 = 2_500_000
    private static let pointcloudBytesPerSecondEstimate: Int64 = 250_000
    private static let csvLogBytesPerSecondEstimate: Int64 = 150_000

    private let textureRegistry: FlutterTextureRegistry
    private let appVersion: String
    private let appBuild: String

    /// Feature flag: when true, spatial data is written as MCAP; when false, uses legacy CSV+ZIP.
    static let useMcapFormat: Bool = true

    // MARK: - Core Sub-components

    private let sessionManager: ArSessionManager = ArSessionManagerImpl()
    private let flutterTextureRenderer = FlutterTextureRenderer()
    private let frameProcessor: ArFrameProcessor = ArFrameProcessorImpl()
    private let imuCollector: ImuCollector = ImuCollectorImpl()
    private let datasetWriter: DatasetWriter
    private let storageManager: StorageManager
    private let rgbSampler: FrameSampler = FrameSamplerImpl(targetFps: videoFpsFixed)
    private let depthSampler: FrameSampler = FrameSamplerImpl(targetFps: videoFpsFixed)
    private let pointCloudSampler: FrameSampler = FrameSamplerImpl(targetFps: videoFpsFixed)
    private let metricsCollector: RecordingMetricsCollector = RecordingMetricsCollectorImpl()
    private let performanceMonitor: PerformanceMonitor = PerformanceMonitorImpl()
    private let videoEncoder: VideoEncoder
    private let videoEncodingCoordinator: VideoEncodingCoordinator
    private let frameProcessingCoordinator: FrameProcessingCoordinator
    private let recordingHealthMonitor = RecordingHealthMonitor()
    private let recordingLifecycleCoordinator = RecordingLifecycleCoordinator()
    private let recordingFinalizationCoordinator = RecordingFinalizationCoordinator()
    private let performanceOptimizer = PerformanceOptimizer()
    private let recordingStateManager = RecordingStateManager()
    private let frameProcessingPipeline = FrameProcessingPipeline()

    // MARK: - Extracted State/Orchestration

    private let metrics = RecordingMetricsState()
    private var healthManager: RuntimeHealthManager!
    private var metadataAssembler: MetadataAssembler!
    private var frameOrchestrator: RecordingFrameOrchestrator!
    private var cameraImuEstimator: CameraImuExtrinsicEstimator!

    // /arkit/imu channel state. Updated every ARFrame regardless of recording
    // state so the first sample after toggling-on doesn't carry a stale dt.
    private var emitArkitImu: Bool = false
    private var arkitImuPrevQuat: simd_quatf?
    private var arkitImuPrevTimestamp: TimeInterval = 0
    private var arkitImuIntrinsicsWritten: Bool = false

    // MARK: - Processing Queues

    private let processingQueue = DispatchQueue(label: "ar.frame.processing", qos: .userInitiated)
    private let writerQueue = DispatchQueue(label: "ar.mcap.writer", qos: .utility)
    private let textureQueue = DispatchQueue(label: "ar.texture.update", qos: .userInteractive)
    private let finalizationQueue = DispatchQueue(label: "ar.recorder.finalization", qos: .utility)
    private let lifecycleLock = NSLock()
    private var isFinalizationInProgress = false

    // Frame-skipping: prevent ARFrame pileup when queues fall behind
    private var _textureInFlightLock = os_unfair_lock()
    private var _textureInFlight = false
    private var _processingInFlightLock = os_unfair_lock()
    private var _processingInFlight = false

    /// Cached display orientation — updated from delegate thread, used for texture rendering.
    /// Avoids accessing UIApplication.shared.connectedScenes off main thread.
    private var cachedDisplayOrientation: UIInterfaceOrientation = .landscapeLeft

    // MARK: - Callbacks

    var onLowStorageWarning: (() -> Void)?
    var onStorageCritical: (() -> Void)?
    private var storageCriticalDelivered = false
    private let storageCriticalLock = NSLock()

    private func fireStorageCriticalOnce() {
        storageCriticalLock.lock()
        let alreadyDelivered = storageCriticalDelivered
        storageCriticalDelivered = true
        storageCriticalLock.unlock()
        guard !alreadyDelivered else { return }
        onStorageCritical?()
    }

    // MARK: - Recording Config

    private var recordingConfig = RecordingConfig.defaultConfig

    // MARK: - Core State

    private var currentState = ArRecordingState.uninitialized
    private var isRecording = false
    private var isPaused = false
    private var releaseInProgress = false
    private var processingFrameCount = 0
    private var lastErrorMessage: String?

    // MARK: - Prepare/arm state
    //
    // `isPrepared` becomes true once the heavy init (MCAP open, encoder
    // configured, IMU primed) finishes. At that point the frame pipeline can
    // run but writes are still gated by `isRecording`. `armStart` flips
    // `isRecording` and captures the actual flip time so post-processing can
    // compute start jitter.
    private var isPrepared = false
    private var scheduledStartLocalNs: Int64 = 0
    private var actualStartLocalNs:    Int64 = 0
    private var scheduledStopLocalNs:  Int64 = 0
    private var actualStopLocalNs:     Int64 = 0
    private var currentSessionDir:     URL? = nil

    // MARK: - Camera / Resolution

    private var sensorWidth: Int = 1920
    private var sensorHeight: Int = 1080
    private var cameraResolution: String = "1920x1080"
    private var recordingResolution: String = "1280x720"
    private var isLowQualityMode: Bool = false
    private var lowQualityReason: String?
    private let upscaleApplied: Bool = false

    // MARK: - Timing

    private var recordingStartTime: Int64 = 0
    private var pauseStartedAtMs: Int64 = 0
    private var totalPausedDurationMs: Int64 = 0
    private var lastTrackingState: String = "STOPPED"

    // MARK: - Video File

    private var currentVideoFile: URL?

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry

        let deviceModel = UIDevice.current.modelName
        let iosVersion = UIDevice.current.systemVersion
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        self.appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        let datasetWriterImpl: DatasetWriter
        if Self.useMcapFormat {
            datasetWriterImpl = MCAPDatasetWriter(
                deviceModel: deviceModel,
                iosVersion: "iOS \(iosVersion)"
            )
        } else {
            datasetWriterImpl = DatasetWriterImpl(
                deviceModel: deviceModel,
                iosVersion: "iOS \(iosVersion)"
            )
        }
        self.datasetWriter = datasetWriterImpl

        self.storageManager = StorageManagerImpl(
            safetyFactor: Self.storageSafetyFactor,
            videoBitrateBitsPerSecond: Int64(Self.videoBitrate1080p),
            depthBytesPerSecondEstimate: Self.depthBytesPerSecondEstimate,
            pointCloudBytesPerSecondEstimate: Self.pointcloudBytesPerSecondEstimate,
            csvLogBytesPerSecondEstimate: Self.csvLogBytesPerSecondEstimate
        )

        let videoEncoderImpl = VideoEncoderImpl(
            logSystem: { [weak datasetWriterImpl] msg in datasetWriterImpl?.logSystem(message: msg)
            },
            recordError: { [weak datasetWriterImpl] msg, err in
                datasetWriterImpl?.logError(message: msg, error: err)
            },
            onEncodedSample: { /* handled by coordinator */  }
        )
        self.videoEncoder = videoEncoderImpl

        let metricsRef = self.metrics  // RecordingMetricsState is a class (reference type)
        self.videoEncodingCoordinator = VideoEncodingCoordinator(
            videoEncoder: videoEncoderImpl,
            logSystem: { [weak datasetWriterImpl] msg in datasetWriterImpl?.logSystem(message: msg)
            },
            recordError: { [weak datasetWriterImpl] msg, err in
                datasetWriterImpl?.logError(message: msg, error: err)
            },
            onEncodedSampleSubmitted: { metricsRef.incrementSubmittedToEncoderFrameCount() }
        )

        self.frameProcessingCoordinator = FrameProcessingCoordinator(frameSampler: rgbSampler)

        super.init()

        // Now wire up closures that reference self
        self.healthManager = RuntimeHealthManager(
            metrics: metrics,
            healthMonitor: recordingHealthMonitor,
            performanceOptimizer: performanceOptimizer,
            performanceMonitor: performanceMonitor,
            datasetWriter: datasetWriter,
            writerQueue: writerQueue,
            recordError: { [weak self] msg, err in self?.recordError(msg, err) }
        )
        healthManager.onLowStorageWarning = { [weak self] in self?.onLowStorageWarning?() }
        healthManager.onStorageCritical = { [weak self] in self?.fireStorageCriticalOnce() }

        self.metadataAssembler = MetadataAssembler(metricsCollector: metricsCollector)

        self.cameraImuEstimator = CameraImuExtrinsicEstimator(deviceModel: deviceModel)

        self.frameOrchestrator = RecordingFrameOrchestrator(
            metrics: metrics,
            healthManager: healthManager,
            frameProcessingPipeline: frameProcessingPipeline,
            frameProcessingCoordinator: frameProcessingCoordinator,
            frameProcessor: frameProcessor,
            rgbSampler: rgbSampler,
            depthSampler: depthSampler,
            pointCloudSampler: pointCloudSampler,
            imuCollector: imuCollector,
            datasetWriter: datasetWriter,
            sessionManager: sessionManager,
            cameraImuEstimator: cameraImuEstimator,
            writerQueue: writerQueue,
            recordError: { [weak self] msg, err in self?.recordError(msg, err) }
        )

        sessionManager.delegate = self
    }

    // MARK: - ArSessionManagerDelegate

    func arSessionManager(_ manager: ArSessionManager, didUpdateFrame frame: ARFrame) {
        lifecycleLock.lock()
        let shouldRenderPreview = !releaseInProgress
        lifecycleLock.unlock()

        guard shouldRenderPreview else { return }

        emitArkitImuIfNeeded(frame: frame)

        // Cache display orientation for texture rendering (avoids UIApplication access off main thread).
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        {
            // Flip orientation because render pipeline includes a horizontal flip
            switch scene.interfaceOrientation {
            case .landscapeLeft: cachedDisplayOrientation = .landscapeRight
            case .landscapeRight: cachedDisplayOrientation = .landscapeLeft
            default: cachedDisplayOrientation = .landscapeLeft
            }
        }

        // --- Texture queue: skip if previous frame still rendering ---
        os_unfair_lock_lock(&_textureInFlightLock)
        let textureIsBusy = _textureInFlight
        if !textureIsBusy { _textureInFlight = true }
        os_unfair_lock_unlock(&_textureInFlightLock)

        if !textureIsBusy {
            // Extract what FlutterTextureRenderer needs BEFORE dispatching — release ARFrame ASAP.
            let capturedImage = frame.capturedImage
            let viewportSize = CGSize(
                width: CGFloat(flutterTextureRenderer.currentPreviewWidth),
                height: CGFloat(flutterTextureRenderer.currentPreviewHeight)
            )
            let displayOrientation = self.cachedDisplayOrientation
            let displayTransform = frame.displayTransform(
                for: displayOrientation, viewportSize: viewportSize)

            textureQueue.async { [weak self] in
                guard let self else { return }
                defer {
                    os_unfair_lock_lock(&self._textureInFlightLock)
                    self._textureInFlight = false
                    os_unfair_lock_unlock(&self._textureInFlightLock)
                }
                self.flutterTextureRenderer.updateFrame(
                    capturedImage: capturedImage,
                    displayTransform: displayTransform
                )
            }
        }

        // --- Processing queue: skip if previous frame still processing ---
        os_unfair_lock_lock(&_processingInFlightLock)
        let processingIsBusy = _processingInFlight
        if !processingIsBusy { _processingInFlight = true }
        os_unfair_lock_unlock(&_processingInFlightLock)

        if !processingIsBusy {
            lifecycleLock.lock()
            processingFrameCount += 1
            lifecycleLock.unlock()

            processingQueue.async { [weak self] in
                guard let self else { return }
                defer {
                    os_unfair_lock_lock(&self._processingInFlightLock)
                    self._processingInFlight = false
                    os_unfair_lock_unlock(&self._processingInFlightLock)

                    self.lifecycleLock.lock()
                    self.processingFrameCount = max(self.processingFrameCount - 1, 0)
                    self.lifecycleLock.unlock()
                }
                self.processFrame(frame)
            }
        }
    }

    private func processFrame(_ frame: ARFrame) {
        lifecycleLock.lock()
        let releasing = releaseInProgress
        lifecycleLock.unlock()
        if releasing { return }

        let loopStartNs = Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)

        let camera = frame.camera
        let isReady = sessionManager.updateTrackingState(camera.trackingState)
        let newTrackingState = sessionManager.getTrackingStateString(camera.trackingState)

        if newTrackingState != lastTrackingState {
            datasetWriter.logTrackingStateTransition(
                previousState: lastTrackingState,
                nextState: newTrackingState,
                timestampNs: Int64(frame.timestamp * 1_000_000_000)
            )
            if lastTrackingState == ArTrackingState.tracking.rawValue
                && newTrackingState != ArTrackingState.tracking.rawValue
            {
                metrics.trackingLossEvents += 1
            }
            lastTrackingState = newTrackingState
        }

        if isReady && currentState == .initializing {
            currentState = .ready
            print("ARKit session ready for recording")
        }

        if isRecording {
            frameOrchestrator.processFrame(
                frame: frame,
                isPaused: isPaused,
                recordingStartTime: recordingStartTime,
                estimateProjectionBytes: { [weak self] elapsedMs in
                    self?.estimateDatasetSizeProjectionBytes(durationMs: elapsedMs) ?? 0
                }
            )
        }

        let loopDurationNs =
            Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000) - loopStartNs
        let loopDurationMs = Double(loopDurationNs) / 1_000_000.0
        if loopDurationMs > 30.0 || metrics.renderLoopIterations % 300 == 0 {
            print(
                "[PERF] processFrame total=\(String(format: "%.1f", loopDurationMs))ms iter=\(metrics.renderLoopIterations) recording=\(isRecording)"
            )
        }

        // Per-second heartbeat so we can prove processFrame is running at all.
        if metrics.renderLoopIterations % 60 == 0 {
            let iter = metrics.renderLoopIterations
            let state = currentState.rawValue
            let heartbeat = "AR[processFrame_heartbeat] iter=\(iter) "
                + "trackingState=\(newTrackingState) "
                + "currentState=\(state) isRecording=\(isRecording)"
            NSLog("%@", heartbeat)
        }

        metrics.renderLoopIterations += 1
        metrics.renderLoopTotalNs += loopDurationNs
    }

    // MARK: - Session Lifecycle

    func initializeSession(preferences: [String: Any?]?) -> [String: Any?] {
        if currentState == .initializing {
            return createErrorResult("Already initializing")
        }
        if currentState == .ready {
            return createSuccessResult(
                depthSupported: sessionManager.isDepthSupported,
                textureId: flutterTextureRenderer.textureId
            )
        }

        currentState = .initializing
        print("ArRecorderImpl: Initializing session...")

        if !sessionManager.checkAvailability() {
            currentState = .error
            return createErrorResult("ARKit not supported on this device")
        }

        if !imuCollector.initialize() {
            print("IMU collector initialization failed, continuing without IMU")
        }

        flutterTextureRenderer.register(with: textureRegistry)

        let rgbH = RecordingConfig.sanitizedRgbVideoHeight(
            preferences?["rgbVideoHeight"] as? Int ?? 720)
        let autoFocus = preferences?["autoFocus"] as? Bool ?? true
        let autoExposure = preferences?["autoExposure"] as? Bool ?? true
        let arkitFps = RecordingConfig.sanitizedArkitFps(preferences?["arkitFps"] as? Int ?? 60)
        emitArkitImu = preferences?["enableInertialDerived"] as? Bool ?? false
        arkitImuIntrinsicsWritten = false
        let presetConfig = RecordingConfig(rgbVideoHeight: rgbH)
        // Preview buffer matches the recorded RGB resolution so the letterboxed
        // preview is WYSIWYG — exactly what gets written, no extra crop. The one
        // exception is 4K: a 3840×2160 BGRA texture pushed to Flutter every frame
        // (~33 MB/frame @ 30 fps) is far more than any screen needs, so we cap the
        // preview at 1080p. The aspect ratio is identical (16:9), so framing stays
        // WYSIWYG even though the recorded video is full 4K.
        let previewWidth: Int
        let previewHeight: Int
        if presetConfig.rgbLandscapeHeight > 1080 {
            previewWidth = 1920
            previewHeight = 1080
        } else {
            previewWidth = presetConfig.rgbLandscapeWidth
            previewHeight = presetConfig.rgbLandscapeHeight
        }
        flutterTextureRenderer.configurePreviewSize(
            width: previewWidth,
            height: previewHeight
        )
        sessionManager.createSession(
            maxCaptureHeight: rgbH,
            autoFocus: autoFocus,
            autoExposure: autoExposure,
            arkitFps: arkitFps
        )
        imuCollector.setReferenceFrame(.xArbitraryZVertical)

        return createSuccessResult(
            state: ArRecordingState.initializing.rawValue,
            depthSupported: sessionManager.isDepthSupported,
            textureId: flutterTextureRenderer.textureId,
            previewWidth: Int64(flutterTextureRenderer.currentPreviewWidth),
            previewHeight: Int64(flutterTextureRenderer.currentPreviewHeight)
        )
    }

    func startRecording(config: RecordingConfig) -> [String: Any?] {
        // Single-device entry point: prepare + immediately arm.
        let prepareResult = _performPrepare(config: config)
        if (prepareResult["success"] as? Bool) == true {
            armStart(atLocalSeconds: CACurrentMediaTime())
        }
        return prepareResult
    }

    /// Active session directory if a recording is prepared or in progress.
    func currentSessionDirectory() -> URL? {
        return currentSessionDir
    }

    /// Atomic arm: enable writes. Lightweight by design — heavy init must already
    /// be complete via `prepareRecording` (or `startRecording`).
    ///
    /// - Parameter atLocalSeconds: the target instant in `CACurrentMediaTime`
    ///   seconds. Used to compute start jitter for metadata.
    func armStart(atLocalSeconds: Double) {
        guard isPrepared else {
            print("ArRecorderImpl.armStart: ignored — not prepared")
            return
        }
        scheduledStartLocalNs = Int64(atLocalSeconds * 1_000_000_000)
        actualStartLocalNs    = Int64(CACurrentMediaTime() * 1_000_000_000)
        // Set the wall-clock recordingStartTime that finalize / getRecordingState
        // depend on. The MCAP duration field still wins when frames exist, but
        // this catches the empty-MCAP case + powers Dart polling.
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        recordingStartTime = nowMs
        totalPausedDurationMs = 0
        pauseStartedAtMs = 0
        isRecording = true
        isPaused = false
        print("ArRecorderImpl.armStart: isRecording=true at local_ns=\(actualStartLocalNs)")
    }

    /// Extracted heavy-init body of `startRecording`. Sets `isPrepared = true`
    /// at the end but does NOT set `isRecording`. Callers are responsible for
    /// invoking `armStart` separately (or immediately, in the single-device case).
    private func _performPrepare(config: RecordingConfig) -> [String: Any?] {
        guard recordingStateManager.canStart(currentState: currentState) else {
            return createErrorResult("Session not ready. Current state: \(currentState.rawValue)")
        }
        guard !isFinalizationInProgress else {
            return createErrorResult("Previous recording is still finalizing. Please wait.")
        }

        guard sessionManager.isSessionReady else {
            return createErrorResult("Tracking not stable. Wait for TRACKING state.")
        }

        emitArkitImu = config.enableInertialDerived
        arkitImuIntrinsicsWritten = false
        arkitImuPrevQuat = nil
        arkitImuPrevTimestamp = 0
        scheduledStartLocalNs = 0
        actualStartLocalNs = 0
        scheduledStopLocalNs = 0
        actualStopLocalNs = 0

        print(
            "ArRecorderImpl: Starting recording... [depth=\(sessionManager.isDepthSupported), mesh=\(sessionManager.isMeshSupported)]"
        )
        currentState = .recording

        let storagePrecheck = verifyStorageHeadroom()
        if !storagePrecheck.0 {
            currentState = .ready
            return createErrorResult(storagePrecheck.1 ?? "Insufficient storage headroom")
        }

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let sessionBaseDir = docsDir?.appendingPathComponent("ar_sessions")
        let sessionDir = datasetWriter.createSessionDirectory(baseDir: sessionBaseDir)
        guard let sessionDir = sessionDir else {
            currentState = .error
            return createErrorResult("Failed to create output directory")
        }
        self.currentSessionDir = sessionDir

        let sensorLandscape = Self.parseLandscapeResolution(
            sessionManager.selectedCameraResolution
        )
        let (sensorLW, sensorLH) =
            sensorLandscape
            ?? (max(sensorWidth, sensorHeight), min(sensorWidth, sensorHeight))
        sensorWidth = sensorLW
        sensorHeight = sensorLH

        let clamped = Self.clampedRgbOutput(
            desiredWidth: config.rgbLandscapeWidth,
            desiredHeight: config.rgbLandscapeHeight,
            sensorLandscapeWidth: sensorLW,
            sensorLandscapeHeight: sensorLH
        )
        let encodeBitrate: Int
        if config.rgbVideoHeight >= 2160 {
            encodeBitrate = Self.videoBitrate4k
        } else if config.rgbVideoHeight >= 1080 {
            encodeBitrate = Self.videoBitrate1080p
        } else {
            encodeBitrate = Self.videoBitrate720p
        }

        // Reset all metrics and health state
        metrics.reset(
            defaultVideoWidth: clamped.width,
            defaultVideoHeight: clamped.height,
            sensorWidth: sensorLW,
            sensorHeight: sensorLH,
            defaultBitrate: encodeBitrate,
            defaultFps: config.maxSpatialHz
        )
        healthManager.reset()
        cameraResolution = sessionManager.selectedCameraResolution
        recordingResolution = "\(metrics.configuredVideoWidth)x\(metrics.configuredVideoHeight)"
        isLowQualityMode = clamped.isLowQuality
        lowQualityReason = clamped.lowQualityReason

        self.recordingConfig = config
        flutterTextureRenderer.configurePreviewSize(
            width: config.rgbLandscapeWidth,
            height: config.rgbLandscapeHeight
        )
        frameProcessor.prepareForRecording()
        recordingStartTime = Int64(Date().timeIntervalSince1970 * 1000)
        pauseStartedAtMs = 0
        totalPausedDurationMs = 0
        rgbSampler.reset()
        depthSampler.reset()
        pointCloudSampler.reset()
        frameOrchestrator.resetForRecordingStart()
        frameOrchestrator.config = config

        guard datasetWriter.initializeWriters() else {
            currentState = .error
            return createErrorResult("Failed to initialize writers")
        }

        let arkitVersion = "ARKit \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
        datasetWriter.logSystem(message: "Session start time: \(Date())")
        datasetWriter.logSystem(message: "Storage path: \(sessionDir.path)")
        datasetWriter.logSystem(message: "Device model: \(UIDevice.current.modelName)")
        datasetWriter.logSystem(message: "iOS version: \(UIDevice.current.systemVersion)")
        datasetWriter.logSystem(message: "ARKit version: \(arkitVersion)")
        datasetWriter.logSystem(message: "Depth supported: \(sessionManager.isDepthSupported)")
        datasetWriter.logSystem(message: "Mesh supported: \(sessionManager.isMeshSupported)")
        datasetWriter.logSystem(message: "Camera resolution: \(cameraResolution)")
        datasetWriter.logSystem(message: "Recording resolution: \(recordingResolution)")

        metrics.targetEncodeFps = config.maxSpatialHz
        metrics.encodeFrameIntervalNs = Int64(1_000_000_000 / metrics.targetEncodeFps)
        metrics.dynamicEncoderMode = "jpeg_to_mcap_\(config.rgbHz)hz"

        rgbSampler.configure(targetFps: config.rgbHz)
        depthSampler.configure(targetFps: config.depthHz)
        pointCloudSampler.configure(targetFps: config.pointCloudHz)
        if config.recordImu {
            imuCollector.configure(hz: config.imuHz)
            imuCollector.start()
            if let mcap = datasetWriter as? MCAPDatasetWriter {
                // Use the same monotonic uptime clock that ARFrame.timestamp and
                // CMDeviceMotion.timestamp emit. Mixing with epoch time corrupts
                // MCAP's start/end-time bookkeeping and balloons the computed
                // recording duration to ~55 years.
                mcap.writeImuIntrinsics(
                    timestampNs: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000),
                    intrinsics: ImuIntrinsics.default,
                    sampleRateHz: config.imuHz
                )
            }
        }
        isPrepared = true

        print("Recording prepared: \(sessionDir.path)")

        return createSuccessResult(
            state: ArRecordingState.recording.rawValue,
            outputDirectory: sessionDir.path,
            isLowQualityMode: isLowQualityMode,
            lowQualityReason: lowQualityReason,
            cameraResolution: cameraResolution,
            recordingResolution: recordingResolution,
            recordingHz: metrics.targetEncodeFps,
            previewWidth: Int64(flutterTextureRenderer.currentPreviewWidth),
            previewHeight: Int64(flutterTextureRenderer.currentPreviewHeight)
        )
    }

    func pauseRecording() -> [String: Any?] {
        guard recordingStateManager.canPause(currentState: currentState) else {
            return createErrorResult("Not recording. Current state: \(currentState.rawValue)")
        }
        let pauseResult = recordingLifecycleCoordinator.pauseRecording(
            nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        isPaused = pauseResult.isPaused
        pauseStartedAtMs = pauseResult.pauseStartedAtMs
        currentState = pauseResult.nextState
        imuCollector.stop()
        // Ensure in-flight writes complete before pausing
        writerQueue.sync {
            self.datasetWriter.pauseWriters()
        }

        return createSuccessResult(
            state: ArRecordingState.paused.rawValue,
            outputDirectory: datasetWriter.getSessionDirectory(),
            isLowQualityMode: isLowQualityMode,
            lowQualityReason: lowQualityReason,
            cameraResolution: cameraResolution,
            recordingResolution: recordingResolution,
            recordingHz: metrics.targetEncodeFps
        )
    }

    func resumeRecording() -> [String: Any?] {
        guard recordingStateManager.canResume(currentState: currentState) else {
            return createErrorResult("Not paused. Current state: \(currentState.rawValue)")
        }
        let resumeResult = recordingLifecycleCoordinator.resumeRecording(
            nowMs: Int64(Date().timeIntervalSince1970 * 1000),
            pauseStartedAtMs: pauseStartedAtMs,
            totalPausedDurationMs: totalPausedDurationMs
        )
        totalPausedDurationMs = resumeResult.totalPausedDurationMs
        pauseStartedAtMs = resumeResult.pauseStartedAtMs
        isPaused = resumeResult.isPaused
        datasetWriter.resumeWriters()
        imuCollector.start()
        currentState = resumeResult.nextState

        return createSuccessResult(
            state: ArRecordingState.recording.rawValue,
            outputDirectory: datasetWriter.getSessionDirectory(),
            isLowQualityMode: isLowQualityMode,
            lowQualityReason: lowQualityReason,
            cameraResolution: cameraResolution,
            recordingResolution: recordingResolution,
            recordingHz: metrics.targetEncodeFps
        )
    }

    func cancelRecording() -> [String: Any?] {
        guard recordingStateManager.canCancel(currentState: currentState) else {
            return createErrorResult("Not recording. Current state: \(currentState.rawValue)")
        }
        let cancelResult = recordingLifecycleCoordinator.cancelRecording()
        currentState = cancelResult.nextState
        isRecording = cancelResult.isRecording
        isPrepared = false
        currentSessionDir = nil
        isPaused = cancelResult.isPaused
        pauseStartedAtMs = cancelResult.pauseStartedAtMs
        totalPausedDurationMs = cancelResult.totalPausedDurationMs

        imuCollector.stop()
        waitForProcessingQueueToDrain()
        abortVideoEncoder()
        let deleted = datasetWriter.deleteSessionDirectory()
        if !deleted {
            currentState = .error
            return createErrorResult("Failed to discard recording files")
        }

        currentState = .ready
        return [
            "success": true,
            "state": ArRecordingState.ready.rawValue,
            "cancelled": true,
            "outputDirectory": nil,
            "error": nil,
        ]
    }

    func stopRecording() -> [String: Any?] {
        // Single-device entry point: disarm immediately, then finalize.
        guard recordingStateManager.canStop(currentState: currentState) else {
            return createErrorResult("Not recording. Current state: \(currentState.rawValue)")
        }
        armStop(atLocalSeconds: CACurrentMediaTime())
        return finalizeRecording()
    }

    /// Atomic disarm: stop accepting writes. Lightweight — does not flush or
    /// finalize. Callers must invoke `finalizeRecording()` afterwards (or, in
    /// the single-device case, call `stopRecording()` which does both).
    func armStop(atLocalSeconds: Double) {
        scheduledStopLocalNs = Int64(atLocalSeconds * 1_000_000_000)
        actualStopLocalNs    = Int64(CACurrentMediaTime() * 1_000_000_000)
        isRecording = false
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let durationMs = recordingStartTime > 0 ? (nowMs - recordingStartTime - totalPausedDurationMs) : -1
        print("ArRecorderImpl.armStop: isRecording=false at local_ns=\(actualStopLocalNs)")
        NSLog("MD[arm_stop_wall] armStop fired at wall_ms=\(nowMs) local_ns=\(actualStopLocalNs) scheduled_local_ns=\(scheduledStopLocalNs) jitter_ns=\(actualStopLocalNs - scheduledStopLocalNs) recordingStart_wall=\(recordingStartTime) elapsed_ms=\(durationMs)")
    }

    /// Heavy stop: drain IMU, export final mesh, compute stats, write metadata,
    /// build ZIP. Returns the same dictionary shape `stopRecording` always did.
    /// Must be called only after `armStop` (or via `stopRecording` which does
    /// both).
    func finalizeRecording() -> [String: Any?] {
        guard recordingStateManager.canStop(currentState: currentState) else {
            return createErrorResult("Not recording. Current state: \(currentState.rawValue)")
        }

        let stopStartTime = CFAbsoluteTimeGetCurrent()
        print("ArRecorderImpl: Stopping recording... [start]")
        currentState = .stopping

        if isPaused {
            if pauseStartedAtMs > 0 {
                totalPausedDurationMs += max(
                    Int64(Date().timeIntervalSince1970 * 1000) - pauseStartedAtMs, 0)
            }
        }
        isPaused = false
        pauseStartedAtMs = 0

        imuCollector.stop()
        let drainStart = CFAbsoluteTimeGetCurrent()
        print(
            "ArRecorderImpl: waitForProcessingQueueToDrain - start (processingFrameCount=\(processingFrameCount))"
        )
        waitForProcessingQueueToDrain()
        let drainElapsed = CFAbsoluteTimeGetCurrent() - drainStart
        print(
            "ArRecorderImpl: waitForProcessingQueueToDrain - done in \(String(format: "%.2f", drainElapsed))s"
        )
        // Process remaining IMU samples
        if recordingConfig.recordImu {
            let remainingSamples = imuCollector.drainSamples()
            if !remainingSamples.isEmpty {
                for sample in remainingSamples {
                    metrics.imuTimestampRange.record(timestampNs: sample.timestampNs)
                }
                datasetWriter.writeImuSamples(samples: remainingSamples)
            }
        }

        // Export final mesh — ARKit's fully accumulated mesh from the entire session
        if recordingConfig.recordMesh, sessionManager.isMeshSupported,
            let anchors = sessionManager.session?.currentFrame?.anchors
        {
            let meshTimestampNs = Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            if let meshData = frameProcessor.extractMeshData(
                anchors: anchors, timestampNs: meshTimestampNs)
            {
                let written = datasetWriter.writeMeshFrame(
                    timestamp: meshTimestampNs, frameData: meshData)
                if written {
                    metrics.incrementMeshFrameCount()
                    print(
                        "ArRecorderImpl: Final mesh exported (\(meshData.totalVertexCount) vertices, \(meshData.totalFaceCount) triangles)"
                    )
                } else {
                    print("ArRecorderImpl: Failed to write final mesh")
                }
            } else {
                print("ArRecorderImpl: No mesh data available at session end")
            }
        }

        // Compute core stats
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let stats = datasetWriter.getRecordingStats()
        let imuSampleCount = (stats["imuSampleCount"] as? Int) ?? 0
        let mcapDurationMs = (stats["mcapDurationMs"] as? Int64) ?? 0
        print("ArRecorderImpl.finalize: nowMs=\(nowMs) recordingStartTime=\(recordingStartTime) totalPausedMs=\(totalPausedDurationMs) mcapDurationMs=\(mcapDurationMs)")

        let coreStats = recordingFinalizationCoordinator.computeCoreStats(
            nowMs: nowMs,
            recordingStartTimeMs: recordingStartTime,
            totalPausedDurationMs: totalPausedDurationMs,
            arkitFrameCount: metrics.arkitFrameCount,
            encodedVideoFrameCount: metrics.encodedVideoFrameCount,
            depthFrameCount: metrics.depthFrameCount,
            pointCloudFrameCount: metrics.pointCloudFrameCount,
            meshFrameCount: metrics.meshFrameCount,
            imuSampleCount: imuSampleCount,
            videoFileSizeBytes: nil,
            mcapDurationMs: mcapDurationMs
        )

        datasetWriter.captureFreeStorageAfterSnapshot()

        let totalBytesWritten = (stats["totalBytesWritten"] as? Int64) ?? 0

        // Assemble metadata
        let finalizationResult = metadataAssembler.assemble(
            input: MetadataAssembler.FinalizationInput(
                metrics: metrics,
                health: healthManager,
                coreStats: coreStats,
                sessionManager: sessionManager,
                frameProcessor: frameProcessor,
                imuCollector: imuCollector,
                datasetWriter: datasetWriter,
                cameraImuEstimator: cameraImuEstimator,
                recordingResolution: recordingResolution,
                cameraResolution: cameraResolution,
                previewWidth: flutterTextureRenderer.currentPreviewWidth,
                previewHeight: flutterTextureRenderer.currentPreviewHeight,
                isLowQualityMode: isLowQualityMode,
                lowQualityReason: lowQualityReason,
                upscaleApplied: upscaleApplied,
                arkitVersion:
                    "ARKit \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)",
                appVersion: appVersion,
                appBuild: appBuild,
                imuSampleCount: imuSampleCount,
                totalBytesWritten: totalBytesWritten,
                estimatedDatasetSizeBytes: estimateDatasetSizeProjectionBytes(
                    durationMs: coreStats.durationMs),
                sizeWarningThresholdBytes: Self.sizeWarningThresholdBytes,
                recordingStartTime: recordingStartTime
            ))

        let durationSeconds = coreStats.durationSeconds
        let outputDir = datasetWriter.getSessionDirectory()

        // Return to ready state immediately — finalization happens in background
        currentState = .ready
        isFinalizationInProgress = true

        let stopElapsed = CFAbsoluteTimeGetCurrent() - stopStartTime
        print(
            "ArRecorderImpl: Recording stopped (sync) in \(String(format: "%.2f", stopElapsed))s: \(outputDir ?? "unknown")"
        )

        // Dispatch remaining finalization work to background queue
        let metadata = finalizationResult.metadata
        let metricsSnapshot = (
            totalErrorsEncountered: metrics.totalErrorsEncountered,
            trackingLossEvents: metrics.trackingLossEvents,
            maxEncoderQueueDepth: metrics.maxEncoderQueueDepth,
            encoderBackpressureDetected: metrics.encoderBackpressureDetected
        )
        let imuFps = durationSeconds > 0.0 ? Double(imuSampleCount) / durationSeconds : 0.0
        let capturedCameraResolution = cameraResolution
        let capturedRecordingResolution = recordingResolution
        let capturedIsLowQualityMode = isLowQualityMode
        let capturedLowQualityReason = lowQualityReason

        let bgTaskId = UIApplication.shared.beginBackgroundTask {
            print("ArRecorderImpl: Background finalization task expired by iOS")
        }


        finalizationQueue.async { [weak self] in
            guard let self = self else { return }

            let metadataWritten = self.datasetWriter.writeMetadata(metadata: metadata)
            if !metadataWritten {
                print("ArRecorderImpl: metadata.json write failed — all strategies exhausted")
            }

            // Log session end info
            self.datasetWriter.logSystem(message: "Session end time: \(Date())")
            self.datasetWriter.logSystem(
                message: "Errors encountered: \(metricsSnapshot.totalErrorsEncountered)")
            self.datasetWriter.logSystem(
                message: "Tracking loss events: \(metricsSnapshot.trackingLossEvents)")

            let sessionSummary = self.recordingFinalizationCoordinator.buildSessionSummary(
                durationSeconds: durationSeconds,
                arkitFps: coreStats.arkitFps,
                encodedVideoFps: coreStats.encodedVideoFps,
                depthFps: coreStats.depthFps,
                meshFps: coreStats.meshFps,
                imuFps: imuFps,
                cameraResolution: capturedCameraResolution,
                recordingResolution: capturedRecordingResolution,
                isLowQualityMode: capturedIsLowQualityMode,
                lowQualityReason: capturedLowQualityReason,
                maxEncoderQueueDepth: metricsSnapshot.maxEncoderQueueDepth,
                encoderBackpressureDetected: metricsSnapshot.encoderBackpressureDetected
            )
            self.datasetWriter.writeSessionSummary(summaryText: sessionSummary)

            print("ArRecorderImpl: finalizeSessionFiles - start (background)")
            let (success, _, error) = self.datasetWriter.createSpatialDataZip()
            print("ArRecorderImpl: finalizeSessionFiles - done (success=\(success))")
            self.datasetWriter.finalizeWriters()
            if !success {
                print("ArRecorderImpl: finalizeSessionFiles failed: \(error ?? "unknown")")
            }

            self.isFinalizationInProgress = false
            print("ArRecorderImpl: Background finalization complete")

            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
            }
        }

        isPrepared = false
        currentSessionDir = nil

        return [
            "success": true,
            "state": ArRecordingState.ready.rawValue,
            "depthSupported": sessionManager.isDepthSupported,
            "meshSupported": sessionManager.isMeshSupported,
            "outputDirectory": outputDir,
            "sessionPath": outputDir,
            "durationSeconds": durationSeconds,
            "framesRecorded": metrics.frameCount,
            "imuSamples": imuSampleCount,
            "galleryUri": nil,
            "isLowQualityMode": isLowQualityMode,
            "lowQualityReason": lowQualityReason,
            "cameraResolution": cameraResolution,
            "recordingResolution": recordingResolution,
            "upscaleApplied": upscaleApplied,
            "error": nil,
        ]
    }

    func getRecordingState() -> [String: Any?] {
        let duration: Int64? =
            isRecording
            ? {
                let activePausedMs: Int64 =
                    (isPaused && pauseStartedAtMs > 0)
                    ? max(Int64(Date().timeIntervalSince1970 * 1000) - pauseStartedAtMs, 0)
                    : 0
                return max(
                    Int64(Date().timeIntervalSince1970 * 1000) - recordingStartTime
                        - totalPausedDurationMs - activePausedMs, 0)
            }() : nil

        return [
            "state": currentState.rawValue,
            "trackingState": lastTrackingState,
            "isRecording": isRecording,
            "isPaused": isPaused,
            "depthSupported": sessionManager.isDepthSupported,
            "meshSupported": sessionManager.isMeshSupported,
            "recordingDuration": duration,
            "frameCount": (isRecording || currentState == .paused) ? metrics.frameCount : nil,
            "textureId": flutterTextureRenderer.textureId,
            "cameraResolution": cameraResolution,
            "recordingResolution": recordingResolution,
            "isLowQualityMode": isLowQualityMode,
            "lowQualityReason": lowQualityReason,
            "recordingHz": recordingConfig.maxSpatialHz,
            "upscaleApplied": upscaleApplied,
            "isFinalizationInProgress": isFinalizationInProgress,
            "error": lastErrorMessage,
        ]
    }

    func checkArAvailability() -> [String: Any?] {
        return ["supported": ARWorldTrackingConfiguration.isSupported]
    }

    func disposeSession() {
        print("ArRecorderImpl: Disposing session...")

        lifecycleLock.lock()
        releaseInProgress = true
        lifecycleLock.unlock()

        if isRecording {
            _ = stopRecording()
        }

        waitForProcessingQueueToDrain()

        currentState = .disposed

        imuCollector.release()
        datasetWriter.release()
        sessionManager.releaseSession()
        flutterTextureRenderer.unregister()
        videoEncoder.release()
        currentVideoFile = nil
        emitArkitImu = false
        arkitImuPrevQuat = nil
        arkitImuPrevTimestamp = 0
        arkitImuIntrinsicsWritten = false

        lifecycleLock.lock()
        releaseInProgress = false
        lifecycleLock.unlock()

        print("Session disposed")
    }

    /// The ARSession delegate can continue delivering frames briefly after stop/dispose is requested.
    /// Waiting here keeps finalization and teardown from racing in-flight processing work.
    /// Drains both processingQueue and writerQueue to ensure all extracted data has been written.
    private func waitForProcessingQueueToDrain() {
        let timeoutSeconds: Double = 10.0
        let startTime = CFAbsoluteTimeGetCurrent()
        var lastLogTime = startTime
        while true {
            processingQueue.sync {}
            lifecycleLock.lock()
            let pendingFrames = processingFrameCount
            lifecycleLock.unlock()
            if pendingFrames == 0 {
                // Processing queue is drained; now drain writer queue to flush all pending writes
                writerQueue.sync {}
                return
            }
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - startTime
            if now - lastLogTime >= 1.0 {
                print(
                    "ArRecorderImpl: waitForProcessingQueueToDrain - still waiting (\(String(format: "%.1f", elapsed))s elapsed, processingFrameCount=\(pendingFrames))"
                )
                lastLogTime = now
            }
            if elapsed >= timeoutSeconds {
                print(
                    "ArRecorderImpl: waitForProcessingQueueToDrain - TIMEOUT after \(String(format: "%.1f", elapsed))s, processingFrameCount=\(pendingFrames) — breaking out"
                )
                // Still drain writer queue on timeout
                writerQueue.sync {}
                break
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    // MARK: - Video Encoder Wrappers

    private func setupVideoEncoder(outputPath: String) -> Bool {
        let result = videoEncodingCoordinator.setupVideoEncoder(
            outputPath: outputPath,
            configuredVideoWidth: metrics.configuredVideoWidth,
            configuredVideoHeight: metrics.configuredVideoHeight,
            targetEncodeFps: metrics.targetEncodeFps,
            targetVideoBitrate: metrics.targetVideoBitrate
        )
        if !result.success { return false }
        metrics.activeVideoBitrate = result.activeVideoBitrate
        metrics.targetVideoBitrate = result.targetVideoBitrate
        metrics.actualVideoWidth = result.actualVideoWidth
        metrics.actualVideoHeight = result.actualVideoHeight
        metrics.encoderSurfaceReady = result.encoderSurfaceReady

        if result.chosenFps != metrics.targetEncodeFps {
            metrics.targetEncodeFps = result.chosenFps
            metrics.encodeFrameIntervalNs = Int64(1_000_000_000 / result.chosenFps)
        }
        if result.chosenWidth != metrics.configuredVideoWidth
            || result.chosenHeight != metrics.configuredVideoHeight
        {
            metrics.configuredVideoWidth = result.chosenWidth
            metrics.configuredVideoHeight = result.chosenHeight
            recordingResolution = "\(result.chosenWidth)x\(result.chosenHeight)"
            isLowQualityMode = true
            lowQualityReason = "encoder_fallback_resolution"
        }
        return true
    }

    private func finalizeVideoEncoder() {
        let result = videoEncodingCoordinator.finalizeVideoEncoder()
        metrics.actualVideoWidth = result.actualVideoWidth
        metrics.actualVideoHeight = result.actualVideoHeight
    }

    private func abortVideoEncoder() {
        videoEncodingCoordinator.releaseVideoEncoder()
        metrics.encoderSurfaceReady = false
        metrics.actualVideoWidth = 0
        metrics.actualVideoHeight = 0
        currentVideoFile = nil
    }

    // MARK: - Utilities

    private func recordError(_ message: String, _ error: Error?) {
        metrics.totalErrorsEncountered += 1
        datasetWriter.logError(message: message, error: error)
    }

    private func estimateDatasetSizeProjectionBytes(durationMs: Int64) -> Int64 {
        let elapsedMs = max(durationMs, 1)
        let stats = datasetWriter.getRecordingStats()
        let bytesWritten = max((stats["totalBytesWritten"] as? Int64) ?? 0, 0)
        let bytesPerMs = Double(bytesWritten) / Double(elapsedMs)
        let projectedForOneMinute = bytesPerMs * 60_000.0
        return Int64(projectedForOneMinute)
    }

    private func verifyStorageHeadroom() -> (Bool, String?) {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let baseDir = docsDir?.appendingPathComponent("ar_sessions") else {
            return (false, "Cannot determine storage path")
        }
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let result = storageManager.verifyHeadroom(
            baseDir: baseDir,
            durationSeconds: Self.storageProjectionDurationSeconds,
            includeDepth: sessionManager.isDepthSupported
        )
        return result
    }

    private static func parseLandscapeResolution(_ raw: String) -> (Int, Int)? {
        let parts = raw.split(separator: "x")
        guard parts.count == 2,
            let a = Int(parts[0]),
            let b = Int(parts[1])
        else { return nil }
        return (max(a, b), min(a, b))
    }

    private static func clampedRgbOutput(
        desiredWidth: Int,
        desiredHeight: Int,
        sensorLandscapeWidth: Int,
        sensorLandscapeHeight: Int
    ) -> (width: Int, height: Int, isLowQuality: Bool, lowQualityReason: String?) {
        if sensorLandscapeWidth >= desiredWidth && sensorLandscapeHeight >= desiredHeight {
            return (
                width: desiredWidth, height: desiredHeight, isLowQuality: false,
                lowQualityReason: nil
            )
        }
        let w = (sensorLandscapeWidth / 16) * 16
        let h = (sensorLandscapeHeight / 16) * 16
        return (
            width: w, height: h, isLowQuality: true,
            lowQualityReason: "camera_resolution_below_target"
        )
    }

    private func createSuccessResult(
        state: String = ArRecordingState.ready.rawValue,
        depthSupported: Bool = false,
        textureId: Int64? = nil,
        outputDirectory: String? = nil,
        isLowQualityMode: Bool = false,
        lowQualityReason: String? = nil,
        cameraResolution: String? = nil,
        recordingResolution: String? = nil,
        recordingHz: Int? = nil,
        previewWidth: Int64? = nil,
        previewHeight: Int64? = nil
    ) -> [String: Any?] {
        lastErrorMessage = nil
        return [
            "success": true,
            "state": state,
            "depthSupported": depthSupported,
            "textureId": textureId,
            "outputDirectory": outputDirectory,
            "isLowQualityMode": isLowQualityMode,
            "lowQualityReason": lowQualityReason,
            "cameraResolution": cameraResolution,
            "recordingResolution": recordingResolution,
            "recordingHz": recordingHz ?? recordingConfig.maxSpatialHz,
            "previewWidth": previewWidth,
            "previewHeight": previewHeight,
            "upscaleApplied": false,
            "error": nil,
        ]
    }

    private func createErrorResult(_ errorMessage: String) -> [String: Any?] {
        lastErrorMessage = errorMessage
        return [
            "success": false,
            "state": currentState.rawValue,
            "depthSupported": sessionManager.isDepthSupported,
            "textureId": flutterTextureRenderer.textureId,
            "outputDirectory": nil,
            "isLowQualityMode": isLowQualityMode,
            "lowQualityReason": lowQualityReason,
            "cameraResolution": cameraResolution,
            "recordingResolution": recordingResolution,
            "recordingHz": recordingConfig.maxSpatialHz,
            "upscaleApplied": upscaleApplied,
            "error": errorMessage,
        ]
    }

    // MARK: - /arkit/imu channel

    /// Emits a per-frame `sensor_msgs/msg/Imu` message on `/arkit/imu`:
    /// orientation comes directly from ARKit's VIO-fused camera transform;
    /// angular velocity is a finite-difference of orientation. Linear
    /// acceleration is not provided (covariance[0] = -1).
    ///
    /// Updates `arkitImuPrevQuat` / `arkitImuPrevTimestamp` every call so
    /// toggling the flag mid-session doesn't carry a stale dt.
    ///
    private func emitArkitImuIfNeeded(frame: ARFrame) {
        let transform = frame.camera.transform
        let qNow = simd_quatf(simd_float3x3(
            simd_make_float3(transform.columns.0),
            simd_make_float3(transform.columns.1),
            simd_make_float3(transform.columns.2)
        ))
        let timestamp = frame.timestamp

        defer {
            arkitImuPrevQuat = qNow
            arkitImuPrevTimestamp = timestamp
        }

        guard isRecording, emitArkitImu,
              let mcap = datasetWriter as? MCAPDatasetWriter else { return }

        // Write intrinsics once per session, the first time we emit a sample.
        if !arkitImuIntrinsicsWritten {
            let timestampNs = Int64(timestamp * 1_000_000_000)
            mcap.writeArkitImuIntrinsics(
                timestampNs: timestampNs,
                intrinsics: ImuIntrinsics.arkit,
                sampleRateHz: sessionManager.activeArkitFps
            )
            arkitImuIntrinsicsWritten = true
        }

        let timestampNs = Int64(timestamp * 1_000_000_000)
        let angularVel: (x: Double, y: Double, z: Double)
        if let qPrev = arkitImuPrevQuat {
            let dt = timestamp - arkitImuPrevTimestamp
            guard dt > 0 else { return }
            let qDelta = simd_normalize(qNow * simd_inverse(qPrev))
            let angle = Double(qDelta.angle)
            if abs(angle) < 1e-6 {
                angularVel = (0, 0, 0)
            } else {
                let axis = simd_normalize(qDelta.axis)
                let scale = angle / dt
                angularVel = (Double(axis.x) * scale, Double(axis.y) * scale, Double(axis.z) * scale)
            }
        } else {
            // First frame after IMU/ARKit (re)init. Emit anyway with ω=0 so
            // the /arkit/imu stream's first message lands on the same ARFrame
            // as /camera/pose. Otherwise this device's IMU starts one frame
            // late and pairs misaligned with the peer when only one side
            // experienced the (re)init at recording start — see attempt 3 in
            angularVel = (0, 0, 0)
        }
        mcap.writeArkitImuSample(
            timestampNs: timestampNs,
            orientation: (Double(qNow.imag.x), Double(qNow.imag.y), Double(qNow.imag.z), Double(qNow.real)),
            angularVelocity: angularVel
        )
    }
}

// MARK: - UIDevice Extension

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// Filesystem-safe slug derived from `modelName` (e.g. "iPhone14,3" → "iphone14_3").
    /// Non-alphanumeric characters collapse to underscores so the slug is safe for use
    /// in session folder names and MCAP filenames.
    var modelSlug: String {
        let lowered = modelName.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber { return c }
            return "_"
        }
        return String(mapped)
    }
}
