import Foundation
import ARKit
import CoreImage

/// Orchestrates per-frame recording logic.
/// Each call to processFrame handles:
/// - ARKit cadence estimation
/// - Tracking transition evaluation
/// - Intrinsics extraction (first frame)
/// - Encoder backpressure gate
/// - RGB video encoding
/// - Pose extraction and writing
/// - Point cloud extraction and writing
/// - Depth extraction and writing
/// - Frame log row writing
/// - IMU sample draining
/// - Post-frame health checks and maintenance
class RecordingFrameOrchestrator {

    private static let jpegQuality: CGFloat = 0.8

    private let metrics: RecordingMetricsState
    private let healthManager: RuntimeHealthManager
    private let frameProcessingPipeline: FrameProcessingPipeline
    private let frameProcessingCoordinator: FrameProcessingCoordinator
    private let frameProcessor: ArFrameProcessor
    private let rgbSampler: FrameSampler
    private let depthSampler: FrameSampler
    private let pointCloudSampler: FrameSampler
    private let imuCollector: ImuCollector
    private let datasetWriter: DatasetWriter
    private let sessionManager: ArSessionManager
    private let cameraImuEstimator: CameraImuExtrinsicEstimator
    private let recordError: (String, Error?) -> Void
    private let writerQueue: DispatchQueue
    private let ciContext = CIContext()
    private var didLogJpegDimensions = false
    private var depthIntrinsicsWritten = false
    private var cameraImuExtrinsicPushed = false

    /// Recording configuration — controls which data channels are captured.
    var config = RecordingConfig.defaultConfig

    // Backpressure: limit pending writerQueue closures to prevent memory buildup
    private var _pendingWriteLock = os_unfair_lock()
    private var _pendingWriteCount: Int = 0
    private static let maxPendingWrites: Int = 3

    init(
        metrics: RecordingMetricsState,
        healthManager: RuntimeHealthManager,
        frameProcessingPipeline: FrameProcessingPipeline,
        frameProcessingCoordinator: FrameProcessingCoordinator,
        frameProcessor: ArFrameProcessor,
        rgbSampler: FrameSampler,
        depthSampler: FrameSampler,
        pointCloudSampler: FrameSampler,
        imuCollector: ImuCollector,
        datasetWriter: DatasetWriter,
        sessionManager: ArSessionManager,
        cameraImuEstimator: CameraImuExtrinsicEstimator,
        writerQueue: DispatchQueue,
        recordError: @escaping (String, Error?) -> Void
    ) {
        self.metrics = metrics
        self.healthManager = healthManager
        self.frameProcessingPipeline = frameProcessingPipeline
        self.frameProcessingCoordinator = frameProcessingCoordinator
        self.frameProcessor = frameProcessor
        self.rgbSampler = rgbSampler
        self.depthSampler = depthSampler
        self.pointCloudSampler = pointCloudSampler
        self.imuCollector = imuCollector
        self.datasetWriter = datasetWriter
        self.sessionManager = sessionManager
        self.cameraImuEstimator = cameraImuEstimator
        self.writerQueue = writerQueue
        self.recordError = recordError
    }

    func resetForRecordingStart() {
        didLogJpegDimensions = false
        cameraImuExtrinsicPushed = false
        // Publish the cached camera↔IMU extrinsic on its dedicated topic as soon as the
        // writers are ready. First-ever recording on a device: cached is nil, and we wait
        // for `maybeFinalize()` to fire mid-session.
        if let cached = cameraImuEstimator.cachedValue() {
            let r = cached.rotationRowMajor
            let t = cached.translationXYZ
            writerQueue.async { [weak self] in
                self?.datasetWriter.setCameraImuExtrinsic(
                    rotationRowMajor: r,
                    translationXYZ: (t.x, t.y, t.z)
                )
            }
            cameraImuExtrinsicPushed = true
        }
    }

    func processFrame(
        frame: ARFrame,
        isPaused: Bool,
        recordingStartTime: Int64,
        estimateProjectionBytes: (Int64) -> Int64
    ) {
        if !frameProcessingPipeline.shouldProcess(isPaused: isPaused, frameTimestamp: frame.timestamp) {
            return
        }

        let timestampNs = Int64(frame.timestamp * 1_000_000_000)
        metrics.incrementArkitFrameCount()
        metrics.globalArFrameIndex += 1
        let globalFrameIndex = metrics.globalArFrameIndex
        metrics.lastObservedArkitTimestampNs = timestampNs
        updateArkitCadenceEstimate(timestampNs)

        let camera = frame.camera
        let trackingState = frameProcessor.extractTrackingState(camera: camera)
        let trackingTransition = frameProcessingPipeline.evaluateTrackingTransition(
            timestampNs: timestampNs,
            trackingState: camera.trackingState,
            trackingPausedAtNs: metrics.trackingPausedAtNs,
            trackingPauseCount: metrics.trackingPauseCount,
            trackingPauseTotalOffsetNs: metrics.trackingPauseTotalOffsetNs,
            wasTrackingInPreviousFrame: metrics.wasTrackingInPreviousFrame,
            depthCadenceResetCount: metrics.depthCadenceResetCount,
            onTrackingPauseOffset: { [weak self] (offsetNs: Int64) in
                self?.rgbSampler.recordTrackingPauseOffset(offsetNs: offsetNs)
                self?.depthSampler.recordTrackingPauseOffset(offsetNs: offsetNs)
                self?.pointCloudSampler.recordTrackingPauseOffset(offsetNs: offsetNs)
            }
        )
        metrics.trackingPausedAtNs = trackingTransition.trackingPausedAtNs
        metrics.trackingPauseCount = trackingTransition.trackingPauseCount
        metrics.trackingPauseTotalOffsetNs = trackingTransition.trackingPauseTotalOffsetNs
        metrics.wasTrackingInPreviousFrame = trackingTransition.wasTrackingInPreviousFrame
        metrics.depthCadenceResetCount = trackingTransition.depthCadenceResetCount
        let isTracking = metrics.wasTrackingInPreviousFrame

        // --- Extract all frame data on processingQueue (while ARFrame is valid) ---

        var pose: [Float]?
        var intrinsics: [String: Any]?
        var pointCloudData: PointCloudFrameData?
        var depthFrame: DepthFrameData?
        var meshData: MeshFrameData?
        var depthIntrinsics: [String: Any]?
        var jpegData: Data?
        var encoded = false

        let shouldSampleRgb = isTracking && config.recordRgb
            && rgbSampler.shouldEncodeFrame(timestampNs: timestampNs)
        let shouldSampleDepth = isTracking && config.recordDepth
            && depthSampler.shouldEncodeFrame(timestampNs: timestampNs)
        let shouldSamplePointCloud = isTracking && config.recordPointCloud
            && pointCloudSampler.shouldEncodeFrame(timestampNs: timestampNs)
        let shouldSampleAnySpatial = shouldSampleRgb || shouldSampleDepth || shouldSamplePointCloud

        if isTracking && !shouldSampleRgb && config.recordRgb {
            metrics.rgbSamplingSkippedCount += 1
        }

        if shouldSampleAnySpatial {
            let sampleStartNs = Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)

            // Extract intrinsics & pose when any spatial channel fires
            intrinsics = frameProcessor.extractIntrinsics(camera: camera, pixelBuffer: frame.capturedImage)
            pose = frameProcessor.extractPose(camera: camera)
            metrics.incrementPoseFrameCount()
            metrics.poseTimestampRange.record(timestampNs: timestampNs)
            if let pose = pose {
                cameraImuEstimator.pushCameraPose(timestampNs: timestampNs, pose: pose)
            }

            // Extract point cloud
            if shouldSamplePointCloud {
                pointCloudData = frameProcessor.extractPointCloudFrame(frame: frame, timestampNs: timestampNs)
                if pointCloudData != nil {
                    metrics.pointCloudTimestampRange.record(timestampNs: timestampNs)
                    metrics.addIndexWithCap(store: &metrics.pointcloudFrameIndices, index: globalFrameIndex)
                    metrics.incrementPointCloudFrameCount()
                } else {
                    metrics.addIndexWithCap(store: &metrics.pointcloudDroppedFrameIndices, index: globalFrameIndex)
                }
            }

            // Extract depth
            if shouldSampleDepth, sessionManager.isDepthSupported {
                metrics.addTimestampWithCap(store: &metrics.depthAssociationCandidateRgbTimestamps, timestampNs: timestampNs)
                metrics.depthAttemptCount += 1
                let depthStartNs = Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
                depthFrame = frameProcessor.extractDepthImage(frame: frame)
                let depthLatencyNs = Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000) - depthStartNs
                metrics.depthAcquisitionSamples += 1
                metrics.depthAcquisitionTotalLatencyNs += depthLatencyNs
                if depthLatencyNs > metrics.depthAcquisitionMaxLatencyNs {
                    metrics.depthAcquisitionMaxLatencyNs = depthLatencyNs
                }

                if depthFrame != nil {
                    metrics.depthSuccessCount += 1
                    metrics.addIndexWithCap(store: &metrics.depthFrameIndices, index: globalFrameIndex)
                    metrics.depthTimestampRange.record(timestampNs: timestampNs)
                    metrics.addTimestampWithCap(store: &metrics.depthFrameTimestamps, timestampNs: timestampNs)
                    metrics.incrementDepthFrameCount()
                } else {
                    metrics.incrementSkippedDepthFrameCount()
                    metrics.addIndexWithCap(store: &metrics.depthDroppedFrameIndices, index: globalFrameIndex)
                }
            }

            // Extract depth intrinsics (once)
            if shouldSampleDepth, !depthIntrinsicsWritten, let depth = depthFrame {
                depthIntrinsics = frameProcessor.extractDepthIntrinsics(camera: camera, depthWidth: depth.width, depthHeight: depth.height)
                if depthIntrinsics != nil {
                    depthIntrinsicsWritten = true
                }
            }

            // JPEG capture
            var jpegElapsedMs: Double = 0.0
            if shouldSampleRgb {
                let jpegStartNs = Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
                jpegData = captureJpeg(pixelBuffer: frame.capturedImage)
                jpegElapsedMs = Double(Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000) - jpegStartNs) / 1_000_000.0
                if jpegData != nil {
                    encoded = true
                    metrics.rgbTimestampRange.record(timestampNs: timestampNs)
                    metrics.addTimestampWithCap(store: &metrics.rgbFrameTimestamps, timestampNs: timestampNs)
                    metrics.addIndexWithCap(store: &metrics.rgbEncodedFrameIndices, index: globalFrameIndex)
                    metrics.incrementEncodedVideoFrameCount()
                    metrics.incrementSubmittedToEncoderFrameCount()
                } else {
                    metrics.rgbEncoderFailureCount += 1
                    metrics.addIndexWithCap(store: &metrics.rgbEncoderFailureFrameIndices, index: globalFrameIndex)
                    metrics.incrementDroppedFrameCount()
                }
            }

            let sampleElapsedMs = Double(Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000) - sampleStartNs) / 1_000_000.0
            if sampleElapsedMs > 20.0 || globalFrameIndex % 150 == 0 {
                print("[PERF] processFrame extraction: total=\(String(format: "%.1f", sampleElapsedMs))ms jpeg=\(String(format: "%.1f", jpegElapsedMs))ms frame=\(globalFrameIndex)")
            }
        }

        // Map ARKit tracking state to plain values for MCAP topic
        let (trackingStateCode, trackingReasonCode, trackingStateStr, trackingReasonStr): (UInt8, UInt8, String, String) = {
            switch camera.trackingState {
            case .notAvailable:
                return (0, 0, "not_available", "none")
            case .limited(let reason):
                switch reason {
                case .initializing:
                    return (1, 1, "limited", "initializing")
                case .excessiveMotion:
                    return (1, 2, "limited", "excessive_motion")
                case .insufficientFeatures:
                    return (1, 3, "limited", "insufficient_features")
                case .relocalizing:
                    return (1, 4, "limited", "relocalizing")
                @unknown default:
                    return (1, 0, "limited", "none")
                }
            case .normal:
                return (2, 0, "normal", "none")
            @unknown default:
                return (0, 0, "not_available", "none")
            }
        }()

        // Drain IMU samples (must happen on processingQueue while collector is active)
        let imuSamples: [ImuSample]
        if config.recordImu {
            imuSamples = imuCollector.drainSamples()
            if !imuSamples.isEmpty {
                for sample in imuSamples {
                    metrics.imuTimestampRange.record(timestampNs: sample.timestampNs)
                }
                cameraImuEstimator.pushImuSamples(imuSamples)
            }
        } else {
            imuSamples = []
        }

        // Camera↔IMU extrinsic finalization. First-ever session on a device: publishes
        // once after ~20 s of sufficient motion. Subsequent sessions still run the
        // solver opportunistically so the cache can be refreshed via EMA at session end.
        if !cameraImuExtrinsicPushed {
            if let extrinsic = cameraImuEstimator.maybeFinalize(currentTimestampNs: timestampNs) {
                let r = extrinsic.rotationRowMajor
                let t = extrinsic.translationXYZ
                let residual = extrinsic.rotationResidualMedianRadS
                let samples = extrinsic.rotationSamples
                let window = extrinsic.calibrationWindowS
                let drift = extrinsic.driftVsCacheDeg
                writerQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.datasetWriter.setCameraImuExtrinsic(
                        rotationRowMajor: r,
                        translationXYZ: (t.x, t.y, t.z)
                    )
                    self.datasetWriter.logSystem(message: String(
                        format: "Camera↔IMU extrinsic finalised: residual=%.4f rad/s samples=%d windowS=%.1f drift=%.2f°",
                        residual, samples, window, drift
                    ))
                }
                cameraImuExtrinsicPushed = true
            }
        } else {
            _ = cameraImuEstimator.maybeFinalize(currentTimestampNs: timestampNs)
        }

        // Capture frame log values before dispatching
        let frameCount = metrics.frameCount
        let depthAvailable = frame.smoothedSceneDepth != nil
        let pointCloudAvailable = frame.rawFeaturePoints != nil
        let meshAvailable = frame.anchors.contains { $0 is ARMeshAnchor }

        // --- Dispatch all writes to writerQueue (MCAPWriter is NOT thread-safe) ---
        // Backpressure: skip frame writes if writerQueue is backed up to prevent memory buildup
        os_unfair_lock_lock(&_pendingWriteLock)
        _pendingWriteCount += 1
        let currentPending = _pendingWriteCount
        os_unfair_lock_unlock(&_pendingWriteLock)

        if currentPending > Self.maxPendingWrites {
            os_unfair_lock_lock(&_pendingWriteLock)
            _pendingWriteCount -= 1
            os_unfair_lock_unlock(&_pendingWriteLock)
            metrics.incrementDroppedFrameCount()
            print("[PERF] BACKPRESSURE DROP: pending=\(currentPending) frame=\(globalFrameIndex)")
            // Still run health checks below, but skip the heavy write dispatch
            healthManager.maybeSampleRuntimeHealth()
            healthManager.maybeRunPeriodicMaintenance()
            syncSamplerStats()
            healthManager.maybeLogSizeProjection(
                recordingStartTimeMs: recordingStartTime,
                estimateProjectionBytes: estimateProjectionBytes
            )
            metrics.frameCount += 1
            return
        }

        writerQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                os_unfair_lock_lock(&self._pendingWriteLock)
                self._pendingWriteCount -= 1
                os_unfair_lock_unlock(&self._pendingWriteLock)
            }

            autoreleasepool {

            if isTracking {
                if let intrinsics = intrinsics {
                    self.datasetWriter.writeIntrinsics(timestampNs: timestampNs, intrinsics: intrinsics)
                }
                if let pose = pose {
                    self.datasetWriter.writePoseRow(timestamp: timestampNs, pose: pose, trackingState: trackingState)
                }
                if self.config.recordPointCloud {
                    self.datasetWriter.writePointCloud(timestamp: timestampNs, frameData: pointCloudData)
                }
                if self.config.recordDepth {
                    if let depth = depthFrame {
                        let depthWritten = self.datasetWriter.writeDepthFrame(timestamp: timestampNs, frameData: depth)
                        if !depthWritten {
                            self.metrics.incrementSkippedDepthFrameCount()
                        }
                    }
                    if let depthIntrinsics = depthIntrinsics {
                        self.datasetWriter.writeDepthIntrinsics(timestampNs: timestampNs, intrinsics: depthIntrinsics)
                    }
                }
                if self.config.recordMesh {
                    if let mesh = meshData {
                        let written = self.datasetWriter.writeMeshFrame(timestamp: timestampNs, frameData: mesh)
                        if !written {
                            self.metrics.addIndexWithCap(store: &self.metrics.meshDroppedFrameIndices, index: globalFrameIndex)
                        }
                    }
                }
            }

            if self.config.recordRgb, let jpegData = jpegData {
                self.datasetWriter.writeCompressedRgbFrame(timestamp: timestampNs, jpegData: jpegData)
            }

            self.datasetWriter.writeTrackingState(
                timestampNs: timestampNs,
                state: trackingStateCode,
                reason: trackingReasonCode,
                stateStr: trackingStateStr,
                reasonStr: trackingReasonStr
            )

            self.datasetWriter.writeFrameLogRow(
                frameIndex: frameCount,
                globalArFrameIndex: globalFrameIndex,
                arkitTimestampNs: timestampNs,
                trackingState: trackingState,
                encoded: encoded,
                depthAvailable: depthAvailable,
                pointCloudAvailable: pointCloudAvailable,
                meshAvailable: meshAvailable
            )

            if self.config.recordImu, !imuSamples.isEmpty {
                self.datasetWriter.writeImuSamples(samples: imuSamples)
            }

            // Write device metrics per-frame (~15Hz) using cached values
            self.healthManager.writeDeviceMetricsForFrame(timestampNs: timestampNs)

            self.datasetWriter.flushRealtimeData(timestampNs: timestampNs)
            } // autoreleasepool
        }

        // Refresh device metrics cache (~every 500ms) on the processing queue
        healthManager.maybeRefreshDeviceMetricsCache()

        healthManager.maybeSampleRuntimeHealth()
        healthManager.maybeRunPeriodicMaintenance()
        syncSamplerStats()
        healthManager.maybeLogSizeProjection(
            recordingStartTimeMs: recordingStartTime,
            estimateProjectionBytes: estimateProjectionBytes
        )

        metrics.frameCount += 1
    }

    // MARK: - Internal Helpers

    private func captureJpeg(pixelBuffer: CVPixelBuffer) -> Data? {
        return autoreleasepool {
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            let sourceWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let sourceHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            let targetW = CGFloat(metrics.configuredVideoWidth)
            let targetH = CGFloat(metrics.configuredVideoHeight)
            let scaleX = targetW / sourceWidth
            let scaleY = targetH / sourceHeight
            let scale = min(scaleX, scaleY)

            if scale < 1.0 {
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }

            if !didLogJpegDimensions {
                let outputWidth = Int(ciImage.extent.width.rounded())
                let outputHeight = Int(ciImage.extent.height.rounded())
                print("RecordingFrameOrchestrator: JPEG frame dimensions source=\(Int(sourceWidth))x\(Int(sourceHeight)) output=\(outputWidth)x\(outputHeight) target=\(Int(targetW))x\(Int(targetH))")
                didLogJpegDimensions = true
            }

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: Self.jpegQuality])
        }
    }

    private func syncSamplerStats() {
        let stats = frameProcessingCoordinator.syncSamplerStats()
        if stats.totalExpectedFrameCount != 0 {
            metrics.totalExpectedFrameCount = stats.totalExpectedFrameCount
        }
        if stats.deterministicFrameIndex != 0 {
            metrics.deterministicFrameIndex = stats.deterministicFrameIndex
        }
        if stats.sessionStartTimestampNs != Int64.min {
            metrics.sessionStartTimestampNs = stats.sessionStartTimestampNs
        }
    }

    private func updateArkitCadenceEstimate(_ arkitTimestampNs: Int64) {
        let stats = frameProcessingCoordinator.updateArkitCadenceEstimate(
            arkitTimestampNs: arkitTimestampNs,
            lastArkitTimestampNsForEstimate: metrics.lastArkitTimestampNsForEstimate,
            arkitCadenceSamples: metrics.arkitCadenceSamples,
            arkitCadenceMeanIntervalNs: metrics.arkitCadenceMeanIntervalNs,
            arkitCadenceM2IntervalNs: metrics.arkitCadenceM2IntervalNs
        )
        metrics.arkitCadenceSamples = stats.samples
        metrics.arkitCadenceMeanIntervalNs = stats.meanIntervalNs
        metrics.arkitCadenceM2IntervalNs = stats.m2IntervalNs
        metrics.lastArkitTimestampNsForEstimate = stats.lastArkitTimestampNsForEstimate
    }
}
