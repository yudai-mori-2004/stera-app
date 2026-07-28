package open.fpvlabs.stera.ar_recorder.data

/**
 * ROS2 .msg schema definitions for MCAP channel registration.
 * These are the textual schema representations used by Foxglove and ROS2 tooling.
 */
object ROS2SchemaDefinitions {

    const val SCHEMA_ENCODING = "ros2msg"
    const val MESSAGE_ENCODING = "cdr"

    // Topic names
    const val POSE_TOPIC = "/camera/pose"
    const val IMU_TOPIC = "/device/imu"
    const val DEPTH_TOPIC = "/camera/depth"
    const val COMPRESSED_RGB_TOPIC = "/camera/rgb/compressed"
    const val POINTCLOUD_TOPIC = "/map/point_cloud"
    const val MESH_TOPIC = "/map/mesh"
    const val MESH_CLOUD_TOPIC = "/map/mesh_cloud"
    const val CAMERA_INFO_TOPIC = "/camera/camera_info"
    const val DEPTH_CAMERA_INFO_TOPIC = "/camera/depth/camera_info"
    const val TF_TOPIC = "/tf"
    const val TRAJECTORY_TOPIC = "/trajectory"
    const val DEVICE_METRICS_TOPIC = "/device/metrics"

    // Schema names
    const val POSE_STAMPED_NAME = "geometry_msgs/msg/PoseStamped"
    const val IMU_NAME = "sensor_msgs/msg/Imu"
    const val IMAGE_NAME = "sensor_msgs/msg/Image"
    const val COMPRESSED_IMAGE_NAME = "sensor_msgs/msg/CompressedImage"
    const val POINT_CLOUD_2_NAME = "sensor_msgs/msg/PointCloud2"
    const val MARKER_NAME = "visualization_msgs/msg/Marker"
    const val CAMERA_INFO_NAME = "sensor_msgs/msg/CameraInfo"
    const val TF_MESSAGE_NAME = "tf2_msgs/msg/TFMessage"
    const val PATH_NAME = "nav_msgs/msg/Path"
    const val DEVICE_METRICS_NAME = "stera/msg/DeviceMetrics"

    @Suppress("MaxLineLength")
    val POSE_STAMPED_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val IMU_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val IMAGE_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val COMPRESSED_IMAGE_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val POINT_CLOUD_2_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val CAMERA_INFO_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val TF_MESSAGE_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val MARKER_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val PATH_SCHEMA = """
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
""".trimIndent()

    @Suppress("MaxLineLength")
    val DEVICE_METRICS_SCHEMA = """
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
""".trimIndent()
}
