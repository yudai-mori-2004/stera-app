import Foundation

/// Owns all per-recording mutable counters, timestamp tracking, and frame index lists.
/// Provides a single `reset()` method to reinitialize everything between recordings.
class RecordingMetricsState {

    static let maxTimestampHistory = 500_000

    // MARK: - Timestamp Range Tracker

    class TimestampRange {
        var minNs: Int64 = Int64.max
        var maxNs: Int64 = Int64.min
        var count: Int64 = 0

        func record(timestampNs: Int64) {
            if timestampNs < minNs { minNs = timestampNs }
            if timestampNs > maxNs { maxNs = timestampNs }
            count += 1
        }

        func startOrZero() -> Int64 { count > 0 ? minNs : 0 }
        func endOrZero() -> Int64 { count > 0 ? maxNs : 0 }
        func durationNsOrZero() -> Int64 { count > 1 ? maxNs - minNs : 0 }

        func reset() {
            minNs = Int64.max
            maxNs = Int64.min
            count = 0
        }
    }

    // MARK: - Atomic Frame Counters (use os_unfair_lock for thread safety)

    private var _lock = os_unfair_lock()

    private var _arcoreFrameCount: Int = 0
    private var _encodedVideoFrameCount: Int = 0
    private var _submittedToEncoderFrameCount: Int = 0
    private var _depthFrameCount: Int = 0
    private var _pointCloudFrameCount: Int = 0
    private var _poseFrameCount: Int = 0
    private var _droppedFrameCount: Int = 0
    private var _skippedDepthFrameCount: Int = 0
    private var _meshFrameCount: Int = 0

    var arkitFrameCount: Int {
        get { withLock { _arcoreFrameCount } }
        set { withLock { _arcoreFrameCount = newValue } }
    }
    var encodedVideoFrameCount: Int {
        get { withLock { _encodedVideoFrameCount } }
        set { withLock { _encodedVideoFrameCount = newValue } }
    }
    var submittedToEncoderFrameCount: Int {
        get { withLock { _submittedToEncoderFrameCount } }
        set { withLock { _submittedToEncoderFrameCount = newValue } }
    }
    var depthFrameCount: Int {
        get { withLock { _depthFrameCount } }
        set { withLock { _depthFrameCount = newValue } }
    }
    var pointCloudFrameCount: Int {
        get { withLock { _pointCloudFrameCount } }
        set { withLock { _pointCloudFrameCount = newValue } }
    }
    var poseFrameCount: Int {
        get { withLock { _poseFrameCount } }
        set { withLock { _poseFrameCount = newValue } }
    }
    var droppedFrameCount: Int {
        get { withLock { _droppedFrameCount } }
        set { withLock { _droppedFrameCount = newValue } }
    }
    var skippedDepthFrameCount: Int {
        get { withLock { _skippedDepthFrameCount } }
        set { withLock { _skippedDepthFrameCount = newValue } }
    }
    var meshFrameCount: Int {
        get { withLock { _meshFrameCount } }
        set { withLock { _meshFrameCount = newValue } }
    }

    func incrementArkitFrameCount() { withLock { _arcoreFrameCount += 1 } }
    func incrementEncodedVideoFrameCount() { withLock { _encodedVideoFrameCount += 1 } }
    func incrementSubmittedToEncoderFrameCount() { withLock { _submittedToEncoderFrameCount += 1 } }
    func incrementDepthFrameCount() { withLock { _depthFrameCount += 1 } }
    func incrementPointCloudFrameCount() { withLock { _pointCloudFrameCount += 1 } }
    func incrementPoseFrameCount() { withLock { _poseFrameCount += 1 } }
    func incrementDroppedFrameCount() { withLock { _droppedFrameCount += 1 } }
    func incrementSkippedDepthFrameCount() { withLock { _skippedDepthFrameCount += 1 } }
    func incrementMeshFrameCount() { withLock { _meshFrameCount += 1 } }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return body()
    }

    // MARK: - Scalar Counters

    var trackingLossEvents: Int = 0
    var sizeWarningLogged: Bool = false
    var frameCount: Int = 0
    var globalArFrameIndex: Int = 0

    // MARK: - Timestamp Ranges

    let rgbTimestampRange = TimestampRange()
    let poseTimestampRange = TimestampRange()
    let depthTimestampRange = TimestampRange()
    let pointCloudTimestampRange = TimestampRange()
    let imuTimestampRange = TimestampRange()
    let meshTimestampRange = TimestampRange()

    // MARK: - Timestamp History

    var rgbFrameTimestamps: [Int64] = []
    var depthFrameTimestamps: [Int64] = []
    var depthAssociationCandidateRgbTimestamps: [Int64] = []

    // MARK: - Frame Index Tracking Lists

    var rgbEncodedFrameIndices: [Int] = []
    var rgbEncoderFailureFrameIndices: [Int] = []
    var depthFrameIndices: [Int] = []
    var depthDroppedFrameIndices: [Int] = []
    var pointcloudFrameIndices: [Int] = []
    var pointcloudDroppedFrameIndices: [Int] = []
    var poseDroppedFrameIndices: [Int] = []
    var meshFrameIndices: [Int] = []
    var meshDroppedFrameIndices: [Int] = []

    // MARK: - Mesh Throttle
    var lastMeshWriteTimestampNs: Int64 = Int64.min

    // MARK: - Render Loop Performance

    var renderLoopIterations: Int64 = 0
    var renderLoopTotalNs: Int64 = 0

    // MARK: - Encoder Queue

    var maxEncoderQueueDepth: Int = 0

    // MARK: - Depth Acquisition Latency

    var depthAcquisitionSamples: Int = 0
    var depthAcquisitionTotalLatencyNs: Int64 = 0
    var depthAcquisitionMaxLatencyNs: Int64 = 0

    // MARK: - Error Tracking

    var totalErrorsEncountered: Int = 0

    // MARK: - Tracking Pause / Depth Cadence

    var trackingPauseDepthSkipCount: Int = 0
    var depthAttemptCount: Int = 0
    var depthSuccessCount: Int = 0
    var depthCadenceResetCount: Int = 0
    var wasTrackingInPreviousFrame: Bool = false

    // MARK: - Tracking Pause Offset

    var trackingPauseCount: Int = 0
    var trackingPauseTotalOffsetNs: Int64 = 0
    var trackingPausedAtNs: Int64 = Int64.min

    // MARK: - Video Encoder State

    var encoderSurfaceReady: Bool = false
    var lastEncodedTimestampNs: Int64 = Int64.min
    var lastSubmittedTimestampNs: Int64 = Int64.min
    var sessionStartTimestampNs: Int64 = Int64.min
    var deterministicFrameIndex: Int64 = 0
    var totalExpectedFrameCount: Int64 = 0
    var configuredVideoWidth: Int = 720
    var configuredVideoHeight: Int = 1280
    var actualVideoWidth: Int = 0
    var actualVideoHeight: Int = 0

    // MARK: - Encoder Interval Statistics (Welford Online)

    var encoderIntervalSamples: Int64 = 0
    var encoderIntervalMeanNs: Double = 0.0
    var encoderIntervalM2Ns: Double = 0.0

    // MARK: - ARKit Cadence Estimation (Welford Online)

    var lastArkitTimestampNsForEstimate: Int64 = Int64.min
    var arkitCadenceSamples: Int64 = 0
    var arkitCadenceMeanIntervalNs: Double = 0.0
    var arkitCadenceM2IntervalNs: Double = 0.0

    // MARK: - RGB Sampling / Encoder Failures

    var rgbSamplingSkippedCount: Int = 0
    var rgbEncoderFailureCount: Int = 0
    var lastObservedArkitTimestampNs: Int64 = Int64.min
    var driftResyncEventCount: Int = 0
    var pointCloudSoftSkipCount: Int = 0

    // MARK: - Encoder Backpressure

    var encoderBackpressureDetected: Bool = false
    var poolStarvationEventCount: Int = 0
    var encoderQueueDepthAfterFix: Int = 0

    // MARK: - Bitrate Adaptation

    var targetEncodeFps: Int = 30
    var targetVideoBitrate: Int = 10_000_000
    var activeVideoBitrate: Int = 10_000_000
    var bitrateReducedCount: Int = 0
    var bitrateRestoreCount: Int = 0
    var bitrateStableSinceMs: Int64 = 0
    var encodeFrameIntervalNs: Int64 = 1_000_000_000 / 30
    var dynamicEncoderMode: String = "deterministic_sampling"

    // MARK: - Depth Association Threshold

    var effectiveDepthAssociationThresholdNs: Int64 = 40_000_000

    // MARK: - Utility

    func addTimestampWithCap(store: inout [Int64], timestampNs: Int64) {
        if store.count >= Self.maxTimestampHistory {
            store.removeFirst()
        }
        store.append(timestampNs)
    }

    func addIndexWithCap(store: inout [Int], index: Int) {
        if store.count >= Self.maxTimestampHistory {
            store.removeFirst()
        }
        store.append(index)
    }

    func encoderQueueDepth() -> Int {
        return max(submittedToEncoderFrameCount - encodedVideoFrameCount, 0)
    }

    // MARK: - Reset

    func reset(
        defaultVideoWidth: Int = 720,
        defaultVideoHeight: Int = 1280,
        sensorWidth: Int = 1920,
        sensorHeight: Int = 1080,
        defaultBitrate: Int = 10_000_000,
        defaultFps: Int = 30,
        depthAssociationThresholdNs: Int64 = 40_000_000
    ) {
        arkitFrameCount = 0
        encodedVideoFrameCount = 0
        submittedToEncoderFrameCount = 0
        depthFrameCount = 0
        pointCloudFrameCount = 0
        poseFrameCount = 0
        droppedFrameCount = 0
        skippedDepthFrameCount = 0
        meshFrameCount = 0

        trackingLossEvents = 0
        sizeWarningLogged = false
        frameCount = 0
        globalArFrameIndex = 0

        rgbTimestampRange.reset()
        poseTimestampRange.reset()
        depthTimestampRange.reset()
        pointCloudTimestampRange.reset()
        imuTimestampRange.reset()
        meshTimestampRange.reset()

        rgbFrameTimestamps.removeAll()
        depthFrameTimestamps.removeAll()
        depthAssociationCandidateRgbTimestamps.removeAll()

        rgbEncodedFrameIndices.removeAll()
        rgbEncoderFailureFrameIndices.removeAll()
        depthFrameIndices.removeAll()
        depthDroppedFrameIndices.removeAll()
        pointcloudFrameIndices.removeAll()
        pointcloudDroppedFrameIndices.removeAll()
        poseDroppedFrameIndices.removeAll()
        meshFrameIndices.removeAll()
        meshDroppedFrameIndices.removeAll()
        lastMeshWriteTimestampNs = Int64.min

        renderLoopIterations = 0
        renderLoopTotalNs = 0
        maxEncoderQueueDepth = 0
        depthAcquisitionSamples = 0
        depthAcquisitionTotalLatencyNs = 0
        depthAcquisitionMaxLatencyNs = 0
        totalErrorsEncountered = 0
        trackingPauseDepthSkipCount = 0
        depthAttemptCount = 0
        depthSuccessCount = 0
        depthCadenceResetCount = 0
        wasTrackingInPreviousFrame = false
        trackingPauseCount = 0
        trackingPauseTotalOffsetNs = 0
        trackingPausedAtNs = Int64.min

        configuredVideoWidth = defaultVideoWidth
        configuredVideoHeight = defaultVideoHeight
        actualVideoWidth = 0
        actualVideoHeight = 0
        encoderSurfaceReady = false
        lastEncodedTimestampNs = Int64.min
        lastSubmittedTimestampNs = Int64.min
        sessionStartTimestampNs = Int64.min
        deterministicFrameIndex = 0
        totalExpectedFrameCount = 0
        encoderIntervalSamples = 0
        encoderIntervalMeanNs = 0.0
        encoderIntervalM2Ns = 0.0

        lastArkitTimestampNsForEstimate = Int64.min
        arkitCadenceSamples = 0
        arkitCadenceMeanIntervalNs = 0.0
        arkitCadenceM2IntervalNs = 0.0

        rgbSamplingSkippedCount = 0
        rgbEncoderFailureCount = 0
        lastObservedArkitTimestampNs = Int64.min
        driftResyncEventCount = 0
        pointCloudSoftSkipCount = 0

        encoderBackpressureDetected = false
        poolStarvationEventCount = 0
        encoderQueueDepthAfterFix = 0

        targetEncodeFps = defaultFps
        targetVideoBitrate = defaultBitrate
        activeVideoBitrate = defaultBitrate
        bitrateReducedCount = 0
        bitrateRestoreCount = 0
        bitrateStableSinceMs = 0
        encodeFrameIntervalNs = Int64(1_000_000_000 / defaultFps)
        dynamicEncoderMode = "deterministic_\(defaultFps)fps_sampling"

        effectiveDepthAssociationThresholdNs = depthAssociationThresholdNs
    }
}
