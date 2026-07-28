import Foundation

/// IMU noise / bias parameters used to populate the `/device/imu/intrinsics`
/// MCAP topic and to fill the covariance fields on per-sample `/device/imu`
/// messages.
///
/// Bias values are intentionally zero: `CMDeviceMotion` already applies
/// Apple's internal bias correction, so the IMU samples we record are
/// (best-effort) bias-free. Noise parameters are conservative MEMS-IMU
/// defaults applicable to recent iPhones; refine after running Allan-variance
/// characterisation on the target hardware.
struct ImuIntrinsics {
    let accelNoiseDensity: Double      // m/s² / √Hz
    let gyroNoiseDensity: Double       // rad/s / √Hz
    let accelBiasRandomWalk: Double    // m/s³ / √Hz
    let gyroBiasRandomWalk: Double     // rad/s² / √Hz
    let accelBias: (x: Double, y: Double, z: Double)
    let gyroBias: (x: Double, y: Double, z: Double)
    let source: String                 // "static_defaults"

    /// Variance per sample for a white-noise process discretised at `sampleRateHz`.
    /// Used to populate the diagonal of `sensor_msgs/msg/Imu` covariance fields.
    func accelVariance(sampleRateHz: Int) -> Double {
        accelNoiseDensity * accelNoiseDensity * Double(sampleRateHz)
    }

    func gyroVariance(sampleRateHz: Int) -> Double {
        gyroNoiseDensity * gyroNoiseDensity * Double(sampleRateHz)
    }

    static let `default` = ImuIntrinsics(
        accelNoiseDensity: 2.0e-3,
        gyroNoiseDensity: 1.5e-4,
        accelBiasRandomWalk: 5.0e-5,
        gyroBiasRandomWalk: 1.0e-5,
        accelBias: (0, 0, 0),
        gyroBias: (0, 0, 0),
        source: "static_defaults"
    )

    /// Intrinsics for the `/arkit/imu` stream. Values are derived from ARKit's
    /// VIO output (orientation + finite-diff angular velocity); accelerometer
    /// is not provided, so its noise density is `NaN`. Gyro noise is set
    /// lower than the raw CoreMotion stream because ARKit's orientation is
    /// already VIO-smoothed.
    static let arkit = ImuIntrinsics(
        accelNoiseDensity: .nan,
        gyroNoiseDensity: 5.0e-5,
        accelBiasRandomWalk: .nan,
        gyroBiasRandomWalk: 1.0e-6,
        accelBias: (0, 0, 0),
        gyroBias: (0, 0, 0),
        source: "arkit_vio_derived"
    )
}
