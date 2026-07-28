import CoreMotion
import Foundation
import simd

struct ImuSample {
    let timestampNs: Int64
    let accelX: Float
    let accelY: Float
    let accelZ: Float
    let gyroX: Float
    let gyroY: Float
    let gyroZ: Float
    let callbackLatencyNs: Int64
    /// CMDeviceMotion fused attitude (device orientation in the collector's
    /// gravity-aligned reference frame). nil for the raw collector, whose
    /// accel/gyro are deliberately un-fused.
    var attitude: simd_quatf? = nil
}

/// One observation of the most recent CoreMotion callback, used by
/// `ClockDomainProbe` to relate the CoreMotion clock (boot-time monotonic) to
/// the `ProcessInfo.systemUptime` clock the video pipeline runs on.
/// - motionTimestampNs: `CMDeviceMotion.timestamp` (or `CMAccelerometerData.timestamp`
///   for the raw collector) converted to ns.
/// - capturedAtUptimeNs: the value of `ProcessInfo.systemUptime * 1e9` read
///   inside the callback. Pairs with `motionTimestampNs` so the probe can
///   compute (a) the IMU↔video offset and (b) how stale this snapshot is.
struct ImuMotionSampleObservation {
    let motionTimestampNs: Int64
    let capturedAtUptimeNs: Int64
}

protocol ImuCollector {
    func initialize() -> Bool
    func configure(hz: Int)
    func setReferenceFrame(_ frame: CMAttitudeReferenceFrame)
    func activeReferenceFrameName() -> String
    func start()
    func stop()
    func drainSamples() -> [ImuSample]
    func getQueueSize() -> Int
    func getFirstTimestampNs() -> Int64?
    func getLastTimestampNs() -> Int64?
    func getAverageCallbackLatencyNs() -> Double
    func getMaxCallbackLatencyNs() -> Int64
    func getCallbackCount() -> Int64
    /// Returns the most recent CoreMotion callback observation, or nil if no
    /// callback has fired yet. Read on whatever thread; implementations must
    /// be thread-safe.
    func getLatestMotionObservation() -> ImuMotionSampleObservation?
    func release()
}
