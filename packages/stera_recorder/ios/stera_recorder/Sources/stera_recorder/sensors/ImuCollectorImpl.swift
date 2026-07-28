import CoreMotion
import Foundation
import simd

/// Collects accelerometer and gyroscope data using CMMotionManager.
/// Samples at 100Hz on a dedicated OperationQueue.
class ImuCollectorImpl: ImuCollector {

    private let motionManager = CMMotionManager()
    private var sampleInterval: TimeInterval = 1.0 / 100.0  // default 100Hz
    private var requestedReferenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical
    private var effectiveReferenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical

    private var lock = os_unfair_lock()
    private var sampleQueue: [ImuSample] = []
    private var isCollecting: Bool = false

    private var firstTimestampNs: Int64?
    private var lastTimestampNs: Int64?
    private var lastCallbackUptimeNs: Int64?
    private var totalCallbackLatencyNs: Int64 = 0
    private var maxCallbackLatencyNs: Int64 = 0
    private var callbackCount: Int64 = 0

    private let operationQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "ar.imu.collection"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()

    func initialize() -> Bool {
        if !motionManager.isDeviceMotionAvailable {
            print("Error: Device motion not available")
            return false
        }

        print("IMU collector initialized")
        return true
    }

    func configure(hz: Int) {
        let sanitized = RecordingConfig.supportedImuHz.contains(hz) ? hz : 100
        sampleInterval = 1.0 / Double(sanitized)
    }

    func setReferenceFrame(_ frame: CMAttitudeReferenceFrame) {
        requestedReferenceFrame = frame
    }

    func activeReferenceFrameName() -> String {
        Self.describeReferenceFrame(effectiveReferenceFrame)
    }

    /// Picks the best available `CMAttitudeReferenceFrame` honouring the
    /// caller's request and falling back when the device can't satisfy it
    /// (e.g. true-north requires location authorisation; magnetic-north
    /// requires a calibrated magnetometer).
    private func resolveReferenceFrame(_ requested: CMAttitudeReferenceFrame) -> CMAttitudeReferenceFrame {
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        if available.contains(requested) { return requested }
        if requested.rawValue == CMAttitudeReferenceFrame.xTrueNorthZVertical.rawValue,
           available.contains(.xMagneticNorthZVertical) {
            print("IMU: true-north unavailable, falling back to magnetic-north")
            return .xMagneticNorthZVertical
        }
        print("IMU: requested reference frame unavailable, falling back to xArbitraryZVertical")
        return .xArbitraryZVertical
    }

    private static func describeReferenceFrame(_ frame: CMAttitudeReferenceFrame) -> String {
        if frame == .xTrueNorthZVertical { return "xTrueNorthZVertical" }
        if frame == .xMagneticNorthZVertical { return "xMagneticNorthZVertical" }
        if frame == .xArbitraryCorrectedZVertical { return "xArbitraryCorrectedZVertical" }
        if frame == .xArbitraryZVertical { return "xArbitraryZVertical" }
        return "unknown(\(frame.rawValue))"
    }

    func start() {
        if isCollecting { return }

        os_unfair_lock_lock(&lock)
        sampleQueue.removeAll()
        firstTimestampNs = nil
        lastTimestampNs = nil
        lastCallbackUptimeNs = nil
        totalCallbackLatencyNs = 0
        maxCallbackLatencyNs = 0
        callbackCount = 0
        os_unfair_lock_unlock(&lock)

        effectiveReferenceFrame = resolveReferenceFrame(requestedReferenceFrame)
        motionManager.deviceMotionUpdateInterval = sampleInterval
        motionManager.startDeviceMotionUpdates(using: effectiveReferenceFrame, to: operationQueue) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            let timestampNs = Int64(data.timestamp * 1_000_000_000)
            let callbackNowNs = Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            let latencyNs = callbackNowNs - timestampNs
            let q = data.attitude.quaternion
            let sample = ImuSample(
                timestampNs: timestampNs,
                accelX: Float(data.userAcceleration.x * 9.81),
                accelY: Float(data.userAcceleration.y * 9.81),
                accelZ: Float(data.userAcceleration.z * 9.81),
                gyroX: Float(data.rotationRate.x),
                gyroY: Float(data.rotationRate.y),
                gyroZ: Float(data.rotationRate.z),
                callbackLatencyNs: latencyNs,
                attitude: simd_quatf(
                    ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)
                )
            )
            self.enqueueSample(sample)
        }

        isCollecting = true
        print("IMU collection started (referenceFrame=\(Self.describeReferenceFrame(effectiveReferenceFrame)))")
    }

    func stop() {
        if !isCollecting { return }
        motionManager.stopDeviceMotionUpdates()
        isCollecting = false
        print("IMU collection stopped")
    }

    func drainSamples() -> [ImuSample] {
        os_unfair_lock_lock(&lock)
        let samples = sampleQueue
        sampleQueue.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
        return samples
    }

    func getQueueSize() -> Int {
        os_unfair_lock_lock(&lock)
        let size = sampleQueue.count
        os_unfair_lock_unlock(&lock)
        return size
    }

    func getFirstTimestampNs() -> Int64? {
        os_unfair_lock_lock(&lock)
        let ts = firstTimestampNs
        os_unfair_lock_unlock(&lock)
        return ts
    }

    func getLastTimestampNs() -> Int64? {
        os_unfair_lock_lock(&lock)
        let ts = lastTimestampNs
        os_unfair_lock_unlock(&lock)
        return ts
    }

    func getAverageCallbackLatencyNs() -> Double {
        os_unfair_lock_lock(&lock)
        let result =
            callbackCount == 0 ? 0.0 : Double(totalCallbackLatencyNs) / Double(callbackCount)
        os_unfair_lock_unlock(&lock)
        return result
    }

    func getMaxCallbackLatencyNs() -> Int64 {
        os_unfair_lock_lock(&lock)
        let result = maxCallbackLatencyNs
        os_unfair_lock_unlock(&lock)
        return result
    }

    func getCallbackCount() -> Int64 {
        os_unfair_lock_lock(&lock)
        let result = callbackCount
        os_unfair_lock_unlock(&lock)
        return result
    }

    func getLatestMotionObservation() -> ImuMotionSampleObservation? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard let ts = lastTimestampNs, let cb = lastCallbackUptimeNs else { return nil }
        return ImuMotionSampleObservation(motionTimestampNs: ts, capturedAtUptimeNs: cb)
    }

    func release() {
        stop()
        os_unfair_lock_lock(&lock)
        sampleQueue.removeAll()
        os_unfair_lock_unlock(&lock)
        print("IMU collector released")
    }

    private func enqueueSample(_ sample: ImuSample) {
        os_unfair_lock_lock(&lock)
        sampleQueue.append(sample)
        if firstTimestampNs == nil {
            firstTimestampNs = sample.timestampNs
        }
        lastTimestampNs = sample.timestampNs
        lastCallbackUptimeNs = sample.timestampNs + sample.callbackLatencyNs
        callbackCount += 1
        totalCallbackLatencyNs += sample.callbackLatencyNs
        if sample.callbackLatencyNs > maxCallbackLatencyNs {
            maxCallbackLatencyNs = sample.callbackLatencyNs
        }
        os_unfair_lock_unlock(&lock)
    }
}
