package open.fpvlabs.stera.ar_recorder.data

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * CDR (Common Data Representation) serializer for ROS2 message types.
 * Produces little-endian, aligned binary data compatible with ROS2/DDS CDR encoding.
 */
object CDRSerializer {

    data class TFTransform(
        val frameId: String,
        val childFrameId: String,
        val tx: Double,
        val ty: Double,
        val tz: Double,
        val qx: Double,
        val qy: Double,
        val qz: Double,
        val qw: Double
    )

    /** Serializes a `geometry_msgs/msg/PoseStamped` message. */
    fun serializePoseStamped(
        timestampNs: Long,
        frameId: String,
        tx: Float, ty: Float, tz: Float,
        qx: Float, qy: Float, qz: Float, qw: Float
    ): ByteArray {
        val buf = CDRBuffer()
        buf.writeCDRHeader()
        buf.writeTime(timestampNs)
        buf.writeString(frameId)
        buf.align(8)
        buf.writeFloat64(tx.toDouble())
        buf.writeFloat64(ty.toDouble())
        buf.writeFloat64(tz.toDouble())
        buf.writeFloat64(qx.toDouble())
        buf.writeFloat64(qy.toDouble())
        buf.writeFloat64(qz.toDouble())
        buf.writeFloat64(qw.toDouble())
        return buf.toByteArray()
    }

    /** Serializes a `sensor_msgs/msg/Imu` message. */
    fun serializeImu(
        timestampNs: Long,
        frameId: String,
        angularVelocity: Triple<Double, Double, Double>? = null,
        linearAcceleration: Triple<Double, Double, Double>? = null
    ): ByteArray {
        val buf = CDRBuffer()
        buf.writeCDRHeader()
        buf.writeTime(timestampNs)
        buf.writeString(frameId)

        // Orientation (Quaternion) - unknown
        buf.align(8)
        buf.writeFloat64(0.0); buf.writeFloat64(0.0)
        buf.writeFloat64(0.0); buf.writeFloat64(0.0)
        // orientation_covariance[9] - unknown
        buf.writeFloat64(-1.0)
        repeat(8) { buf.writeFloat64(0.0) }

        // Angular velocity
        if (angularVelocity != null) {
            buf.writeFloat64(angularVelocity.first)
            buf.writeFloat64(angularVelocity.second)
            buf.writeFloat64(angularVelocity.third)
        } else {
            buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(0.0)
        }
        // angular_velocity_covariance[9]
        if (angularVelocity != null) {
            repeat(9) { buf.writeFloat64(0.0) }
        } else {
            buf.writeFloat64(-1.0)
            repeat(8) { buf.writeFloat64(0.0) }
        }

        // Linear acceleration
        if (linearAcceleration != null) {
            buf.writeFloat64(linearAcceleration.first)
            buf.writeFloat64(linearAcceleration.second)
            buf.writeFloat64(linearAcceleration.third)
        } else {
            buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(0.0)
        }
        // linear_acceleration_covariance[9]
        if (linearAcceleration != null) {
            repeat(9) { buf.writeFloat64(0.0) }
        } else {
            buf.writeFloat64(-1.0)
            repeat(8) { buf.writeFloat64(0.0) }
        }

        return buf.toByteArray()
    }

    /** Serializes a `sensor_msgs/msg/CompressedImage`. */
    fun serializeCompressedImage(
        timestampNs: Long,
        frameId: String,
        format: String,
        imageData: ByteArray,
        imageDataLength: Int = imageData.size
    ): ByteArray {
        val buf = CDRBuffer(imageDataLength + 64) // payload dominates; size once
        buf.writeCDRHeader()
        buf.writeTime(timestampNs)
        buf.writeString(frameId)
        // format (e.g. "jpeg")
        buf.writeString(format)
        // data (sequence of uint8)
        buf.writeUInt32(imageDataLength)
        buf.writeRawBytes(imageData, 0, imageDataLength)
        return buf.toByteArray()
    }

    /** Serializes a `sensor_msgs/msg/Image` for depth data. */
    fun serializeImage(
        timestampNs: Long,
        frameId: String,
        height: Int,
        width: Int,
        encoding: String,
        isBigEndian: Boolean,
        step: Int,
        imageData: ByteArray,
        imageDataLength: Int = imageData.size
    ): ByteArray {
        val buf = CDRBuffer(imageDataLength + 96) // depth payload dominates; size once
        buf.writeCDRHeader()
        buf.writeTime(timestampNs)
        buf.writeString(frameId)
        buf.writeUInt32(height)
        buf.writeUInt32(width)
        buf.writeString(encoding)
        buf.writeUInt8(if (isBigEndian) 1 else 0)
        buf.align(4)
        buf.writeUInt32(step)
        buf.writeUInt32(imageDataLength)
        buf.writeRawBytes(imageData, 0, imageDataLength)
        return buf.toByteArray()
    }

    /** Serializes a `sensor_msgs/msg/PointCloud2`. */
    fun serializePointCloud2(
        timestampNs: Long,
        frameId: String,
        pointCount: Int,
        pointData: ByteArray,
        pointDataOffset: Int,
        pointDataLength: Int
    ): ByteArray {
        val buf = CDRBuffer(pointDataLength + 192) // point payload dominates; size once
        buf.writeCDRHeader()
        buf.writeTime(timestampNs)
        buf.writeString(frameId)
        buf.writeUInt32(1) // height = 1 (unorganized)
        buf.writeUInt32(pointCount) // width

        // fields: sequence of PointField (4 fields)
        buf.writeUInt32(4)
        val fieldNames = arrayOf("x", "y", "z", "confidence")
        val fieldOffsets = intArrayOf(0, 4, 8, 12)
        val fieldDatatype: Byte = 7 // FLOAT32
        for (i in 0..3) {
            buf.writeString(fieldNames[i])
            buf.writeUInt32(fieldOffsets[i])
            buf.writeUInt8(fieldDatatype.toInt())
            buf.align(4)
            buf.writeUInt32(1) // count
        }

        buf.writeUInt8(0) // is_bigendian
        buf.align(4)
        buf.writeUInt32(16) // point_step
        buf.writeUInt32(16 * pointCount) // row_step
        buf.writeUInt32(pointDataLength) // data sequence length
        buf.writeRawBytes(pointData, pointDataOffset, pointDataLength)
        buf.writeUInt8(1) // is_dense
        return buf.toByteArray()
    }

    fun serializeDeviceMetrics(
        timestampNs: Long,
        frameId: String,
        batteryLevel: Float,
        batteryState: Int,
        batteryStateStr: String,
        cpuUsage: Float,
        memoryUsedMb: Double,
        memoryAvailableMb: Double,
        thermalState: Int,
        thermalStateStr: String,
        deviceModel: String
    ): ByteArray {
        val buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(timestampNs)
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
        buf.writeFloat64(memoryUsedMb)
        // memory_available_mb (float64)
        buf.writeFloat64(memoryAvailableMb)
        // thermal_state (uint8)
        buf.writeUInt8(thermalState)
        // thermal_state_str (string)
        buf.align(4)
        buf.writeString(thermalStateStr)
        // device_model (string)
        buf.writeString(deviceModel)
        return buf.toByteArray()
    }

    /** Serializes a `tf2_msgs/msg/TFMessage` with one or more transforms. */
    fun serializeTFMessage(
        timestampNs: Long,
        transforms: List<TFTransform>
    ): ByteArray {
        val buf = CDRBuffer()
        buf.writeCDRHeader()
        // transforms: sequence of TransformStamped
        buf.writeUInt32(transforms.size)
        for (transform in transforms) {
            // TransformStamped.header
            buf.writeTime(timestampNs)
            buf.writeString(transform.frameId)
            // child_frame_id
            buf.writeString(transform.childFrameId)
            // Transform.translation (Vector3)
            buf.align(8)
            buf.writeFloat64(transform.tx)
            buf.writeFloat64(transform.ty)
            buf.writeFloat64(transform.tz)
            // Transform.rotation (Quaternion)
            buf.writeFloat64(transform.qx)
            buf.writeFloat64(transform.qy)
            buf.writeFloat64(transform.qz)
            buf.writeFloat64(transform.qw)
        }
        return buf.toByteArray()
    }

    /** Serializes a `visualization_msgs/msg/Marker` for mesh data (TRIANGLE_LIST). */
    fun serializeMarker(
        timestampNs: Long,
        frameId: String,
        points: FloatArray,  // [x0,y0,z0, x1,y1,z1, ...]
        pointCount: Int
    ): ByteArray {
        val buf = CDRBuffer(pointCount * 24 + 256) // 3×float64 per point + header/pose/color
        buf.writeCDRHeader()
        // Header
        buf.writeTime(timestampNs)
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
        buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(0.0) // position
        buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(1.0) // orientation
        // scale (1,1,1)
        buf.writeFloat64(1.0); buf.writeFloat64(1.0); buf.writeFloat64(1.0)
        // color (white, full alpha)
        buf.writeFloat32(1.0f); buf.writeFloat32(1.0f); buf.writeFloat32(1.0f); buf.writeFloat32(1.0f)
        // lifetime (0 = forever)
        buf.writeInt32(0); buf.writeUInt32(0)
        // frame_locked
        buf.writeUInt8(0)
        // points: sequence of Point
        buf.align(4)
        buf.writeUInt32(pointCount)
        for (i in 0 until pointCount) {
            buf.align(8)
            buf.writeFloat64(points[i * 3].toDouble())
            buf.writeFloat64(points[i * 3 + 1].toDouble())
            buf.writeFloat64(points[i * 3 + 2].toDouble())
        }
        // colors: empty sequence
        buf.writeUInt32(0)
        // text
        buf.writeString("")
        // mesh_resource
        buf.writeString("")
        // mesh_use_embedded_materials
        buf.writeUInt8(0)
        return buf.toByteArray()
    }

    /**
     * Serializes a `nav_msgs/msg/Path`.
     * poses: array of [timestampNs, x, y, z, qx, qy, qz, qw] per pose
     */
    fun serializePath(
        timestampNs: Long,
        frameId: String,
        poses: List<PoseEntry>
    ): ByteArray {
        val buf = CDRBuffer()
        buf.writeCDRHeader()
        // Header
        buf.writeTime(timestampNs)
        buf.writeString(frameId)
        // poses: sequence of PoseStamped
        buf.writeUInt32(poses.size)
        for (pose in poses) {
            // PoseStamped.header
            buf.writeTime(pose.timestampNs)
            buf.writeString(frameId)
            // PoseStamped.pose.position
            buf.align(8)
            buf.writeFloat64(pose.x.toDouble())
            buf.writeFloat64(pose.y.toDouble())
            buf.writeFloat64(pose.z.toDouble())
            // PoseStamped.pose.orientation
            buf.writeFloat64(pose.qx.toDouble())
            buf.writeFloat64(pose.qy.toDouble())
            buf.writeFloat64(pose.qz.toDouble())
            buf.writeFloat64(pose.qw.toDouble())
        }
        return buf.toByteArray()
    }

    /** Serializes a `sensor_msgs/msg/CameraInfo`. */
    fun serializeCameraInfo(
        timestampNs: Long,
        frameId: String,
        height: Int,
        width: Int,
        fx: Double,
        fy: Double,
        cx: Double,
        cy: Double
    ): ByteArray {
        val buf = CDRBuffer()
        buf.writeCDRHeader()
        buf.writeTime(timestampNs)
        buf.writeString(frameId)
        buf.writeUInt32(height)
        buf.writeUInt32(width)
        buf.writeString("plumb_bob")
        buf.writeUInt32(0) // D (empty sequence)
        // K[9]
        buf.align(8)
        buf.writeFloat64(fx);  buf.writeFloat64(0.0); buf.writeFloat64(cx)
        buf.writeFloat64(0.0); buf.writeFloat64(fy);  buf.writeFloat64(cy)
        buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(1.0)
        // R[9] - identity
        buf.writeFloat64(1.0); buf.writeFloat64(0.0); buf.writeFloat64(0.0)
        buf.writeFloat64(0.0); buf.writeFloat64(1.0); buf.writeFloat64(0.0)
        buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(1.0)
        // P[12]
        buf.writeFloat64(fx);  buf.writeFloat64(0.0); buf.writeFloat64(cx); buf.writeFloat64(0.0)
        buf.writeFloat64(0.0); buf.writeFloat64(fy);  buf.writeFloat64(cy); buf.writeFloat64(0.0)
        buf.writeFloat64(0.0); buf.writeFloat64(0.0); buf.writeFloat64(1.0); buf.writeFloat64(0.0)
        // binning_x, binning_y
        buf.writeUInt32(0)
        buf.writeUInt32(0)
        // ROI
        buf.writeUInt32(0) // x_offset
        buf.writeUInt32(0) // y_offset
        buf.writeUInt32(0) // height
        buf.writeUInt32(0) // width
        buf.writeUInt8(0)  // do_rectify
        return buf.toByteArray()
    }
}

/** Pose data for trajectory accumulation. */
data class PoseEntry(
    val timestampNs: Long,
    val x: Float, val y: Float, val z: Float,
    val qx: Float, val qy: Float, val qz: Float, val qw: Float
)

/**
 * CDR byte buffer with alignment and little-endian encoding.
 */
class CDRBuffer(initialCapacity: Int = 4096) {
    // Callers that know their dominant payload size (image/point bytes) pass it
    // here so the buffer is sized once up front instead of doubling+copying the
    // whole buffer ~log2(payload/4KB) times as a large message is written.
    private var data = ByteArray(if (initialCapacity > 4096) initialCapacity else 4096)
    private var position = 0

    fun writeCDRHeader() {
        ensureCapacity(4)
        data[position++] = 0x00 // CDR_LE
        data[position++] = 0x01 // little-endian
        data[position++] = 0x00
        data[position++] = 0x00
    }

    /** Aligns to boundary relative to byte 4 (after CDR encapsulation header). */
    fun align(alignment: Int) {
        val remainder = (position - 4) % alignment
        if (remainder != 0) {
            val padding = alignment - remainder
            ensureCapacity(padding)
            repeat(padding) { data[position++] = 0 }
        }
    }

    fun writeUInt8(value: Int) {
        ensureCapacity(1)
        data[position++] = value.toByte()
    }

    fun writeUInt32(value: Int) {
        align(4)
        ensureCapacity(4)
        data[position++] = (value and 0xFF).toByte()
        data[position++] = ((value shr 8) and 0xFF).toByte()
        data[position++] = ((value shr 16) and 0xFF).toByte()
        data[position++] = ((value shr 24) and 0xFF).toByte()
    }

    fun writeInt32(value: Int) {
        align(4)
        ensureCapacity(4)
        data[position++] = (value and 0xFF).toByte()
        data[position++] = ((value shr 8) and 0xFF).toByte()
        data[position++] = ((value shr 16) and 0xFF).toByte()
        data[position++] = ((value shr 24) and 0xFF).toByte()
    }

    fun writeFloat32(value: Float) {
        align(4)
        ensureCapacity(4)
        val bits = java.lang.Float.floatToIntBits(value)
        data[position++] = (bits and 0xFF).toByte()
        data[position++] = ((bits shr 8) and 0xFF).toByte()
        data[position++] = ((bits shr 16) and 0xFF).toByte()
        data[position++] = ((bits shr 24) and 0xFF).toByte()
    }

    fun writeFloat64(value: Double) {
        align(8)
        ensureCapacity(8)
        val bits = java.lang.Double.doubleToLongBits(value)
        data[position++] = (bits and 0xFF).toByte()
        data[position++] = ((bits shr 8) and 0xFF).toByte()
        data[position++] = ((bits shr 16) and 0xFF).toByte()
        data[position++] = ((bits shr 24) and 0xFF).toByte()
        data[position++] = ((bits shr 32) and 0xFF).toByte()
        data[position++] = ((bits shr 40) and 0xFF).toByte()
        data[position++] = ((bits shr 48) and 0xFF).toByte()
        data[position++] = ((bits shr 56) and 0xFF).toByte()
    }

    /** Writes a CDR string: uint32 length (including null terminator) + UTF-8 bytes + null byte. */
    fun writeString(value: String) {
        val utf8 = value.toByteArray(Charsets.UTF_8)
        writeUInt32(utf8.size + 1) // length includes null terminator
        ensureCapacity(utf8.size + 1)
        System.arraycopy(utf8, 0, data, position, utf8.size)
        position += utf8.size
        data[position++] = 0 // null terminator
    }

    /** Writes a builtin_interfaces/Time from nanoseconds. */
    fun writeTime(ns: Long) {
        val sec = (ns / 1_000_000_000L).toInt()
        val nanosec = (ns % 1_000_000_000L).toInt()
        writeInt32(sec)
        writeUInt32(nanosec)
    }

    fun writeRawBytes(bytes: ByteArray, offset: Int = 0, length: Int = bytes.size) {
        ensureCapacity(length)
        System.arraycopy(bytes, offset, data, position, length)
        position += length
    }

    fun toByteArray(): ByteArray = data.copyOfRange(0, position)

    private fun ensureCapacity(needed: Int) {
        if (position + needed > data.size) {
            data = data.copyOf(maxOf(data.size * 2, position + needed))
        }
    }
}
