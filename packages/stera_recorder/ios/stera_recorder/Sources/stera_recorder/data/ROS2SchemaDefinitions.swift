import Foundation

/// ROS2 .msg schema definitions for MCAP channel registration.
/// These are the textual schema representations used by Foxglove and ROS2 tooling.
enum ROS2SchemaDefinitions {

    // MARK: - Schema Encodings

    static let schemaEncoding = "ros2msg"
    static let messageEncoding = "cdr"

    // MARK: - Topic Names

    static let poseTopic = "/camera/pose"
    static let imuTopic = "/device/imu"
    static let depthTopic = "/camera/depth"
    static let compressedRgbTopic = "/camera/rgb/compressed"
    static let pointCloudTopic = "/map/point_cloud"
    static let meshTopic = "/map/mesh"
    static let meshCloudTopic = "/map/mesh_cloud"
    static let cameraInfoTopic = "/camera/camera_info"
    static let depthCameraInfoTopic = "/camera/depth/camera_info"
    static let tfTopic = "/tf"
    static let trajectoryTopic = "/trajectory"
    static let trackingStateTopic = "/camera/tracking_state"
    static let deviceMetricsTopic = "/device/metrics"
    static let imuIntrinsicsTopic = "/device/imu/intrinsics"
    static let arkitImuTopic = "/arkit/imu"
    static let arkitImuIntrinsicsTopic = "/arkit/imu/intrinsics"
    /// Static rigid transform camera_link → imu_frame, estimated on-device by
    /// `CameraImuExtrinsicEstimator`. Single TFMessage emitted at session start (or
    /// once the first-session estimate finalises). Schema: tf2_msgs/msg/TFMessage.
    static let cameraImuExtrinsicsTopic = "/device/camera_imu_extrinsics"
    // MARK: - Schema Names

    static let poseStampedName = "geometry_msgs/msg/PoseStamped"
    static let imuName = "sensor_msgs/msg/Imu"
    static let imageName = "sensor_msgs/msg/Image"
    static let compressedImageName = "sensor_msgs/msg/CompressedImage"
    static let pointCloud2Name = "sensor_msgs/msg/PointCloud2"
    static let markerName = "visualization_msgs/msg/Marker"
    static let cameraInfoName = "sensor_msgs/msg/CameraInfo"
    static let tfMessageName = "tf2_msgs/msg/TFMessage"
    static let pathName = "nav_msgs/msg/Path"
    static let trackingStateName = "stera/msg/TrackingState"
    static let deviceMetricsName = "stera/msg/DeviceMetrics"

    static let imuIntrinsicsName = "stera/msg/ImuIntrinsics"

    // MARK: - Schema Definitions (.msg format)

    // swiftlint:disable line_length

    static let poseStampedSchema = """
std_msgs/msg/Header header
geometry_msgs/msg/Pose pose
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: geometry_msgs/msg/Pose
geometry_msgs/msg/Point position
geometry_msgs/msg/Quaternion orientation
================================================================================
MSG: geometry_msgs/msg/Point
float64 x
float64 y
float64 z
================================================================================
MSG: geometry_msgs/msg/Quaternion
float64 x
float64 y
float64 z
float64 w
"""

    static let imuSchema = """
std_msgs/msg/Header header
geometry_msgs/msg/Quaternion orientation
float64[9] orientation_covariance
geometry_msgs/msg/Vector3 angular_velocity
float64[9] angular_velocity_covariance
geometry_msgs/msg/Vector3 linear_acceleration
float64[9] linear_acceleration_covariance
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: geometry_msgs/msg/Quaternion
float64 x
float64 y
float64 z
float64 w
================================================================================
MSG: geometry_msgs/msg/Vector3
float64 x
float64 y
float64 z
"""

    static let imageSchema = """
std_msgs/msg/Header header
uint32 height
uint32 width
string encoding
uint8 is_bigendian
uint32 step
uint8[] data
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
"""

    static let compressedImageSchema = """
std_msgs/msg/Header header
string format
uint8[] data
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
"""

    static let pointCloud2Schema = """
std_msgs/msg/Header header
uint32 height
uint32 width
sensor_msgs/msg/PointField[] fields
bool is_bigendian
uint32 point_step
uint32 row_step
uint8[] data
bool is_dense
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: sensor_msgs/msg/PointField
string name
uint32 offset
uint8 datatype
uint32 count
"""

    static let markerSchema = """
std_msgs/msg/Header header
string ns
int32 id
int32 type
int32 action
geometry_msgs/msg/Pose pose
geometry_msgs/msg/Vector3 scale
std_msgs/msg/ColorRGBA color
builtin_interfaces/msg/Duration lifetime
bool frame_locked
geometry_msgs/msg/Point[] points
std_msgs/msg/ColorRGBA[] colors
string text
string mesh_resource
bool mesh_use_embedded_materials
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: geometry_msgs/msg/Pose
geometry_msgs/msg/Point position
geometry_msgs/msg/Quaternion orientation
================================================================================
MSG: geometry_msgs/msg/Point
float64 x
float64 y
float64 z
================================================================================
MSG: geometry_msgs/msg/Quaternion
float64 x
float64 y
float64 z
float64 w
================================================================================
MSG: geometry_msgs/msg/Vector3
float64 x
float64 y
float64 z
================================================================================
MSG: std_msgs/msg/ColorRGBA
float32 r
float32 g
float32 b
float32 a
================================================================================
MSG: builtin_interfaces/msg/Duration
int32 sec
uint32 nanosec
"""

    static let cameraInfoSchema = """
std_msgs/msg/Header header
uint32 height
uint32 width
string distortion_model
float64[] d
float64[9] k
float64[9] r
float64[12] p
uint32 binning_x
uint32 binning_y
sensor_msgs/msg/RegionOfInterest roi
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: sensor_msgs/msg/RegionOfInterest
uint32 x_offset
uint32 y_offset
uint32 height
uint32 width
bool do_rectify
"""

    static let tfMessageSchema = """
geometry_msgs/msg/TransformStamped[] transforms
================================================================================
MSG: geometry_msgs/msg/TransformStamped
std_msgs/msg/Header header
string child_frame_id
geometry_msgs/msg/Transform transform
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: geometry_msgs/msg/Transform
geometry_msgs/msg/Vector3 translation
geometry_msgs/msg/Quaternion rotation
================================================================================
MSG: geometry_msgs/msg/Vector3
float64 x
float64 y
float64 z
================================================================================
MSG: geometry_msgs/msg/Quaternion
float64 x
float64 y
float64 z
float64 w
"""

    static let pathSchema = """
std_msgs/msg/Header header
geometry_msgs/msg/PoseStamped[] poses
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: geometry_msgs/msg/PoseStamped
std_msgs/msg/Header header
geometry_msgs/msg/Pose pose
================================================================================
MSG: geometry_msgs/msg/Pose
geometry_msgs/msg/Point position
geometry_msgs/msg/Quaternion orientation
================================================================================
MSG: geometry_msgs/msg/Point
float64 x
float64 y
float64 z
================================================================================
MSG: geometry_msgs/msg/Quaternion
float64 x
float64 y
float64 z
float64 w
"""

    static let trackingStateSchema = """
std_msgs/msg/Header header
uint8 state
uint8 reason
string state_str
string reason_str
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
"""

    static let deviceMetricsSchema = """
std_msgs/msg/Header header
float32 battery_level
uint8 battery_state
string battery_state_str
float32 cpu_usage
float64 memory_used_mb
float64 memory_available_mb
uint8 thermal_state
string thermal_state_str
string device_model
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
"""

    static let imuIntrinsicsSchema = """
std_msgs/msg/Header header
float64 accel_noise_density
float64 gyro_noise_density
float64 accel_bias_random_walk
float64 gyro_bias_random_walk
geometry_msgs/msg/Vector3 accel_bias
geometry_msgs/msg/Vector3 gyro_bias
uint32 sample_rate_hz
string source
================================================================================
MSG: std_msgs/msg/Header
builtin_interfaces/msg/Time stamp
string frame_id
================================================================================
MSG: builtin_interfaces/msg/Time
int32 sec
uint32 nanosec
================================================================================
MSG: geometry_msgs/msg/Vector3
float64 x
float64 y
float64 z
"""

    // swiftlint:enable line_length
}
