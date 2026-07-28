import Foundation

/// CDR (Common Data Representation) serializer for ROS2 message types.
/// Produces little-endian, aligned binary data compatible with ROS2/DDS CDR encoding.
enum CDRSerializer {

    struct TFTransform {
        let frameId: String
        let childFrameId: String
        let translation: (x: Double, y: Double, z: Double)
        let rotation: (x: Double, y: Double, z: Double, w: Double)
    }

    // MARK: - ROS2 PoseStamped

    /// Serializes a `geometry_msgs/msg/PoseStamped` message.
    /// - Parameters:
    ///   - timestampNs: Timestamp in nanoseconds
    ///   - frameId: Frame identifier (e.g. "device")
    ///   - position: [x, y, z] as Float (will be written as Float64)
    ///   - orientation: [qx, qy, qz, qw] as Float (will be written as Float64)
    static func serializePoseStamped(
        timestampNs: Int64,
        frameId: String,
        position: (x: Float, y: Float, z: Float),
        orientation: (x: Float, y: Float, z: Float, w: Float)
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // Pose.position (Point: 3x float64)
        buf.align(8)
        buf.writeFloat64(Double(position.x))
        buf.writeFloat64(Double(position.y))
        buf.writeFloat64(Double(position.z))
        // Pose.orientation (Quaternion: 4x float64)
        buf.writeFloat64(Double(orientation.x))
        buf.writeFloat64(Double(orientation.y))
        buf.writeFloat64(Double(orientation.z))
        buf.writeFloat64(Double(orientation.w))
        return buf.data
    }

    // MARK: - ROS2 Imu

    /// Serializes a `sensor_msgs/msg/Imu` message.
    /// `angularVelocityVariance` / `linearAccelerationVariance`, when provided,
    /// populate the diagonal of the corresponding 3x3 covariance matrix.
    static func serializeImu(
        timestampNs: Int64,
        frameId: String,
        orientation: (x: Double, y: Double, z: Double, w: Double)? = nil,
        angularVelocity: (x: Double, y: Double, z: Double)? = nil,
        linearAcceleration: (x: Double, y: Double, z: Double)? = nil,
        orientationVariance: Double? = nil,
        angularVelocityVariance: Double? = nil,
        linearAccelerationVariance: Double? = nil
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)

        // Orientation (Quaternion)
        buf.align(8)
        if let o = orientation {
            buf.writeFloat64(o.x)
            buf.writeFloat64(o.y)
            buf.writeFloat64(o.z)
            buf.writeFloat64(o.w)
        } else {
            buf.writeFloat64(0); buf.writeFloat64(0)
            buf.writeFloat64(0); buf.writeFloat64(0)
        }
        writeDiagonalCovariance3x3(into: &buf, variance: orientation == nil ? nil : orientationVariance, presentIfMissing: orientation != nil)

        // Angular velocity (Vector3)
        if let av = angularVelocity {
            buf.writeFloat64(av.x)
            buf.writeFloat64(av.y)
            buf.writeFloat64(av.z)
        } else {
            buf.writeFloat64(0); buf.writeFloat64(0); buf.writeFloat64(0)
        }
        writeDiagonalCovariance3x3(into: &buf, variance: angularVelocity == nil ? nil : angularVelocityVariance, presentIfMissing: angularVelocity != nil)

        // Linear acceleration (Vector3)
        if let la = linearAcceleration {
            buf.writeFloat64(la.x)
            buf.writeFloat64(la.y)
            buf.writeFloat64(la.z)
        } else {
            buf.writeFloat64(0); buf.writeFloat64(0); buf.writeFloat64(0)
        }
        writeDiagonalCovariance3x3(into: &buf, variance: linearAcceleration == nil ? nil : linearAccelerationVariance, presentIfMissing: linearAcceleration != nil)

        return buf.data
    }

    /// Writes a 3x3 covariance matrix (9 float64s) with `variance` on the diagonal.
    /// If `variance` is nil and `presentIfMissing` is true, the matrix is all zeros
    /// (per ROS convention: "covariance unknown but quantity is provided").
    /// If `presentIfMissing` is false, the matrix's [0] is set to -1 (quantity not provided).
    private static func writeDiagonalCovariance3x3(into buf: inout CDRBuffer, variance: Double?, presentIfMissing: Bool) {
        if let v = variance {
            buf.writeFloat64(v);  buf.writeFloat64(0); buf.writeFloat64(0)
            buf.writeFloat64(0);  buf.writeFloat64(v); buf.writeFloat64(0)
            buf.writeFloat64(0);  buf.writeFloat64(0); buf.writeFloat64(v)
        } else if presentIfMissing {
            for _ in 0..<9 { buf.writeFloat64(0) }
        } else {
            buf.writeFloat64(-1)
            for _ in 1..<9 { buf.writeFloat64(0) }
        }
    }

    // MARK: - stera ImuIntrinsics

    /// Serializes a `stera/msg/ImuIntrinsics` message.
    static func serializeImuIntrinsics(
        timestampNs: Int64,
        frameId: String,
        intrinsics: ImuIntrinsics,
        sampleRateHz: UInt32
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // Scalar noise parameters (float64)
        buf.align(8)
        buf.writeFloat64(intrinsics.accelNoiseDensity)
        buf.writeFloat64(intrinsics.gyroNoiseDensity)
        buf.writeFloat64(intrinsics.accelBiasRandomWalk)
        buf.writeFloat64(intrinsics.gyroBiasRandomWalk)
        // accel_bias (Vector3)
        buf.writeFloat64(intrinsics.accelBias.x)
        buf.writeFloat64(intrinsics.accelBias.y)
        buf.writeFloat64(intrinsics.accelBias.z)
        // gyro_bias (Vector3)
        buf.writeFloat64(intrinsics.gyroBias.x)
        buf.writeFloat64(intrinsics.gyroBias.y)
        buf.writeFloat64(intrinsics.gyroBias.z)
        // sample_rate_hz (uint32)
        buf.writeUInt32(sampleRateHz)
        // source (string)
        buf.writeString(intrinsics.source)
        return buf.data
    }

    // MARK: - ROS2 CompressedImage

    /// Serializes a `sensor_msgs/msg/CompressedImage`.
    static func serializeCompressedImage(
        timestampNs: Int64,
        frameId: String,
        format: String,
        imageData: Data
    ) -> Data {
        var buf = CDRBuffer()
        buf.reserveCapacity(imageData.count + 64) // payload dominates; avoid realloc churn
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // format (e.g. "jpeg")
        buf.writeString(format)
        // data (sequence of uint8)
        buf.writeUInt32(UInt32(imageData.count))
        buf.writeRawBytes(imageData)
        return buf.data
    }

    // MARK: - ROS2 Image (depth)

    /// Serializes a `sensor_msgs/msg/Image` for depth data.
    static func serializeImage(
        timestampNs: Int64,
        frameId: String,
        height: UInt32,
        width: UInt32,
        encoding: String,
        isBigEndian: Bool,
        step: UInt32,
        imageData: Data
    ) -> Data {
        var buf = CDRBuffer()
        buf.reserveCapacity(imageData.count + 96) // depth payload dominates; avoid realloc churn
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // height, width
        buf.writeUInt32(height)
        buf.writeUInt32(width)
        // encoding
        buf.writeString(encoding)
        // is_bigendian (uint8)
        buf.writeUInt8(isBigEndian ? 1 : 0)
        // step
        buf.align(4)
        buf.writeUInt32(step)
        // data (sequence of uint8)
        buf.writeUInt32(UInt32(imageData.count))
        buf.writeRawBytes(imageData)
        return buf.data
    }

    // MARK: - ROS2 PointCloud2

    /// Serializes a `sensor_msgs/msg/PointCloud2`.
    /// Fields: x(float32), y(float32), z(float32), confidence(float32).
    static func serializePointCloud2(
        timestampNs: Int64,
        frameId: String,
        pointCount: UInt32,
        pointData: Data
    ) -> Data {
        var buf = CDRBuffer()
        buf.reserveCapacity(pointData.count + 192) // point payload dominates; avoid realloc churn
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // height = 1 (unorganized)
        buf.writeUInt32(1)
        // width = pointCount
        buf.writeUInt32(pointCount)

        // fields: sequence of PointField (4 fields)
        buf.writeUInt32(4) // sequence length
        // PointField: name(string), offset(uint32), datatype(uint8), count(uint32)
        let fieldNames = ["x", "y", "z", "confidence"]
        let fieldOffsets: [UInt32] = [0, 4, 8, 12]
        let fieldDatatype: UInt8 = 7 // FLOAT32
        for i in 0..<4 {
            buf.writeString(fieldNames[i])
            buf.writeUInt32(fieldOffsets[i])
            buf.writeUInt8(fieldDatatype)
            buf.align(4)
            buf.writeUInt32(1)
        }

        // is_bigendian (bool = uint8)
        buf.writeUInt8(0)
        // point_step
        buf.align(4)
        buf.writeUInt32(16) // 4 floats * 4 bytes
        // row_step
        buf.writeUInt32(16 * pointCount)
        // data (sequence of uint8)
        buf.writeUInt32(UInt32(pointData.count))
        buf.writeRawBytes(pointData)
        // is_dense
        buf.writeUInt8(1)
        return buf.data
    }

    // MARK: - ROS2 Marker (visualization_msgs/msg/Marker)

    /// Serializes a `visualization_msgs/msg/Marker` for mesh data (TRIANGLE_LIST).
    /// `points` is a flat array of vertex positions [x0,y0,z0, x1,y1,z1, ...] already expanded from triangles.
    static func serializeMarker(
        timestampNs: Int64,
        frameId: String,
        points: [(Double, Double, Double)]
    ) -> Data {
        var buf = CDRBuffer()
        buf.reserveCapacity(points.count * 24 + 256) // 3×float64 per point + header/pose/color
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // ns (namespace)
        buf.writeString("")
        // id
        buf.writeInt32(0)
        // type = TRIANGLE_LIST (11)
        buf.writeInt32(11)
        // action = ADD (0)
        buf.writeInt32(0)
        // pose (identity)
        buf.align(8)
        buf.writeFloat64(0); buf.writeFloat64(0); buf.writeFloat64(0) // position
        buf.writeFloat64(0); buf.writeFloat64(0); buf.writeFloat64(0); buf.writeFloat64(1) // orientation
        // scale (1,1,1)
        buf.writeFloat64(1); buf.writeFloat64(1); buf.writeFloat64(1)
        // color (white, full alpha)
        buf.writeFloat32(1.0); buf.writeFloat32(1.0); buf.writeFloat32(1.0); buf.writeFloat32(1.0)
        // lifetime (0 = forever)
        buf.writeInt32(0); buf.writeUInt32(0)
        // frame_locked
        buf.writeUInt8(0)
        // points: sequence of Point
        buf.align(4)
        buf.writeUInt32(UInt32(points.count))
        for p in points {
            buf.align(8)
            buf.writeFloat64(p.0)
            buf.writeFloat64(p.1)
            buf.writeFloat64(p.2)
        }
        // colors: empty sequence
        buf.writeUInt32(0)
        // text
        buf.writeString("")
        // mesh_resource
        buf.writeString("")
        // mesh_use_embedded_materials
        buf.writeUInt8(0)
        return buf.data
    }

    /// Serializes a single positioned `visualization_msgs/msg/Marker` (e.g. a
    /// SPHERE at a shared-anchor's 6-DoF, or a TEXT_VIEW_FACING label). Unlike
    /// `serializeMarker` (hardcoded TRIANGLE_LIST mesh), this carries a full
    /// pose — position + orientation — so the marker's `pose` field is the
    /// genuine 6-DoF, readable programmatically even though a sphere glyph
    /// doesn't depict orientation. `lifetime` is 0 (forever) so anchors
    /// accumulate in the 3D view.
    static func serializeMarkerPose(
        timestampNs: Int64,
        frameId: String,
        namespace: String,
        id: Int32,
        markerType: Int32,
        position: (Double, Double, Double),
        orientation: (Double, Double, Double, Double),  // x, y, z, w
        scale: (Double, Double, Double),
        color: (Float, Float, Float, Float),            // r, g, b, a
        text: String
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // ns / id / type / action(ADD=0)
        buf.writeString(namespace)
        buf.writeInt32(id)
        buf.writeInt32(markerType)
        buf.writeInt32(0)
        // pose
        buf.align(8)
        buf.writeFloat64(position.0); buf.writeFloat64(position.1); buf.writeFloat64(position.2)
        buf.writeFloat64(orientation.0); buf.writeFloat64(orientation.1)
        buf.writeFloat64(orientation.2); buf.writeFloat64(orientation.3)
        // scale
        buf.writeFloat64(scale.0); buf.writeFloat64(scale.1); buf.writeFloat64(scale.2)
        // color
        buf.writeFloat32(color.0); buf.writeFloat32(color.1); buf.writeFloat32(color.2); buf.writeFloat32(color.3)
        // lifetime (0 = forever)
        buf.writeInt32(0); buf.writeUInt32(0)
        // frame_locked
        buf.writeUInt8(0)
        // points / colors: empty sequences
        buf.align(4)
        buf.writeUInt32(0)
        buf.writeUInt32(0)
        // text
        buf.writeString(text)
        // mesh_resource / mesh_use_embedded_materials
        buf.writeString("")
        buf.writeUInt8(0)
        return buf.data
    }

    // MARK: - ROS2 Path (nav_msgs/msg/Path)

    /// Serializes a `nav_msgs/msg/Path` from accumulated pose entries.
    static func serializePath(
        timestampNs: Int64,
        frameId: String,
        poses: [(timestampNs: Int64, x: Float, y: Float, z: Float, qx: Float, qy: Float, qz: Float, qw: Float)]
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // poses: sequence of PoseStamped
        buf.writeUInt32(UInt32(poses.count))
        for pose in poses {
            // PoseStamped.header
            buf.writeTime(ns: pose.timestampNs)
            buf.writeString(frameId)
            // PoseStamped.pose.position
            buf.align(8)
            buf.writeFloat64(Double(pose.x))
            buf.writeFloat64(Double(pose.y))
            buf.writeFloat64(Double(pose.z))
            // PoseStamped.pose.orientation
            buf.writeFloat64(Double(pose.qx))
            buf.writeFloat64(Double(pose.qy))
            buf.writeFloat64(Double(pose.qz))
            buf.writeFloat64(Double(pose.qw))
        }
        return buf.data
    }

    // MARK: - ROS2 CameraInfo

    /// Serializes a `sensor_msgs/msg/CameraInfo`.
    static func serializeCameraInfo(
        timestampNs: Int64,
        frameId: String,
        height: UInt32,
        width: UInt32,
        fx: Double,
        fy: Double,
        cx: Double,
        cy: Double
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // height, width
        buf.writeUInt32(height)
        buf.writeUInt32(width)
        // distortion_model
        buf.writeString("plumb_bob")
        // D (sequence of float64) — empty
        buf.writeUInt32(0)
        // K[9] — camera intrinsic matrix (row-major)
        buf.align(8)
        buf.writeFloat64(fx);  buf.writeFloat64(0);  buf.writeFloat64(cx)
        buf.writeFloat64(0);   buf.writeFloat64(fy); buf.writeFloat64(cy)
        buf.writeFloat64(0);   buf.writeFloat64(0);  buf.writeFloat64(1)
        // R[9] — identity
        buf.writeFloat64(1); buf.writeFloat64(0); buf.writeFloat64(0)
        buf.writeFloat64(0); buf.writeFloat64(1); buf.writeFloat64(0)
        buf.writeFloat64(0); buf.writeFloat64(0); buf.writeFloat64(1)
        // P[12] — projection matrix
        buf.writeFloat64(fx);  buf.writeFloat64(0);  buf.writeFloat64(cx); buf.writeFloat64(0)
        buf.writeFloat64(0);   buf.writeFloat64(fy); buf.writeFloat64(cy); buf.writeFloat64(0)
        buf.writeFloat64(0);   buf.writeFloat64(0);  buf.writeFloat64(1);  buf.writeFloat64(0)
        // binning_x, binning_y
        buf.writeUInt32(0)
        buf.writeUInt32(0)
        // ROI
        buf.writeUInt32(0) // x_offset
        buf.writeUInt32(0) // y_offset
        buf.writeUInt32(0) // height
        buf.writeUInt32(0) // width
        buf.writeUInt8(0)  // do_rectify
        return buf.data
    }

    // MARK: - stera TrackingState

    /// Serializes a `stera/msg/TrackingState` message.
    /// - Parameters:
    ///   - state: 0=not_available, 1=limited, 2=normal
    ///   - reason: 0=none, 1=initializing, 2=excessive_motion, 3=insufficient_features, 4=relocalizing
    static func serializeTrackingState(
        timestampNs: Int64,
        frameId: String,
        state: UInt8,
        reason: UInt8,
        stateStr: String,
        reasonStr: String
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // state, reason
        buf.writeUInt8(state)
        buf.writeUInt8(reason)
        // state_str, reason_str
        buf.align(4)
        buf.writeString(stateStr)
        buf.writeString(reasonStr)
        return buf.data
    }

    // MARK: - DeviceMetrics

    static func serializeDeviceMetrics(
        timestampNs: Int64,
        frameId: String,
        batteryLevel: Float,
        batteryState: UInt8,
        batteryStateStr: String,
        cpuUsage: Float,
        memoryUsedMb: Double,
        memoryAvailableMb: Double,
        thermalState: UInt8,
        thermalStateStr: String,
        deviceModel: String
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(ns: timestampNs)
        buf.writeString(frameId)
        // battery_level (float32)
        buf.align(4)
        buf.writeFloat32(batteryLevel)
        // battery_state (uint8)
        buf.writeUInt8(batteryState)
        // battery_state_str (string)
        buf.align(4)
        buf.writeString(batteryStateStr)
        // cpu_usage (float32)
        buf.writeFloat32(cpuUsage)
        // memory_used_mb (float64)
        buf.align(8)
        buf.writeFloat64(Double(memoryUsedMb))
        // memory_available_mb (float64)
        buf.writeFloat64(Double(memoryAvailableMb))
        // thermal_state (uint8)
        buf.writeUInt8(thermalState)
        // thermal_state_str (string)
        buf.align(4)
        buf.writeString(thermalStateStr)
        // device_model (string)
        buf.writeString(deviceModel)
        return buf.data
    }

    // MARK: - ROS2 TFMessage

    /// Serializes a `tf2_msgs/msg/TFMessage` with one or more transforms.
    static func serializeTFMessage(
        timestampNs: Int64,
        transforms: [TFTransform]
    ) -> Data {
        var buf = CDRBuffer()
        buf.writeCDRHeader()
        // transforms: sequence of TransformStamped
        buf.writeUInt32(UInt32(transforms.count))
        for transform in transforms {
            // TransformStamped.header
            buf.writeTime(ns: timestampNs)
            buf.writeString(transform.frameId)
            // child_frame_id
            buf.writeString(transform.childFrameId)
            // Transform.translation (Vector3)
            buf.align(8)
            buf.writeFloat64(transform.translation.x)
            buf.writeFloat64(transform.translation.y)
            buf.writeFloat64(transform.translation.z)
            // Transform.rotation (Quaternion)
            buf.writeFloat64(transform.rotation.x)
            buf.writeFloat64(transform.rotation.y)
            buf.writeFloat64(transform.rotation.z)
            buf.writeFloat64(transform.rotation.w)
        }
        return buf.data
    }
}

// MARK: - CDR Buffer

/// A byte buffer that handles CDR alignment and little-endian encoding.
struct CDRBuffer {
    private(set) var data = Data()

    /// Pre-sizes the backing buffer so the stream of small scalar appends below
    /// doesn't trigger repeated geometric reallocations as the message grows.
    /// Callers that know their dominant payload size (image/point bytes) should
    /// reserve up front.
    mutating func reserveCapacity(_ minimumCapacity: Int) {
        data.reserveCapacity(minimumCapacity)
    }

    /// Writes the 4-byte CDR encapsulation header (little-endian, options=0).
    mutating func writeCDRHeader() {
        data.append(0x00) // CDR_LE
        data.append(0x01) // encoding = little-endian
        data.append(0x00) // options
        data.append(0x00) // options
    }

    /// Aligns to the given boundary relative to byte 4 (after the CDR encapsulation header).
    /// This matches the XCDR1 convention used by Foxglove's CDR reader.
    mutating func align(_ alignment: Int) {
        let remainder = (data.count - 4) % alignment
        if remainder != 0 {
            let padding = alignment - remainder
            data.append(contentsOf: [UInt8](repeating: 0, count: padding))
        }
    }

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeInt8(_ value: Int8) {
        data.append(UInt8(bitPattern: value))
    }

    mutating func writeInt64(_ value: Int64) {
        align(8)
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeUInt16(_ value: UInt16) {
        align(2)
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeUInt32(_ value: UInt32) {
        align(4)
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeInt32(_ value: Int32) {
        align(4)
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeUInt64(_ value: UInt64) {
        align(8)
        var v = value.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeFloat32(_ value: Float) {
        align(4)
        var v = value.bitPattern.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func writeFloat64(_ value: Double) {
        align(8)
        var v = value.bitPattern.littleEndian
        data.append(UnsafeBufferPointer(start: &v, count: 1))
    }

    /// Writes a CDR string: uint32 length (including null terminator) + UTF-8 bytes + null byte.
    mutating func writeString(_ value: String) {
        let utf8 = value.utf8
        writeUInt32(UInt32(utf8.count + 1)) // length includes null terminator
        data.append(contentsOf: utf8) // append the view directly — no intermediate Array
        data.append(0x00) // null terminator
    }

    /// Writes a builtin_interfaces/Time from nanoseconds.
    mutating func writeTime(ns: Int64) {
        let sec = Int32(ns / 1_000_000_000)
        let nanosec = UInt32(ns % 1_000_000_000)
        writeInt32(sec)
        writeUInt32(nanosec)
    }

    mutating func writeRawBytes(_ bytes: Data) {
        data.append(bytes)
    }
}
