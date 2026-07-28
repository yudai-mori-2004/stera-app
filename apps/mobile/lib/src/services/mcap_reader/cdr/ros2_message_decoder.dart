import "dart:typed_data";

import "package:stera/src/services/mcap_reader/cdr/cdr_deserializer.dart";
import "package:stera/src/services/mcap_reader/cdr/scene3d.dart";

/// Raw 16UC1 depth frame extracted from a `sensor_msgs/msg/Image`.
class DecodedDepthFrame {
  final int width;
  final int height;
  final Uint16List values;

  const DecodedDepthFrame({
    required this.width,
    required this.height,
    required this.values,
  });
}

/// One decoded MCAP message, shaped for display: an ordered list of
/// field → value rows, plus binary payloads for the visual topics and
/// renderable geometry for the spatial ones.
class DecodedMcapMessage {
  final List<MapEntry<String, String>> fields;
  final Uint8List? jpegBytes;
  final DecodedDepthFrame? depth;
  final Scene3D? scene;

  const DecodedMcapMessage({
    required this.fields,
    this.jpegBytes,
    this.depth,
    this.scene,
  });
}

/// Decodes the CDR payloads of every schema written by the app's recorder
/// (see `CDRSerializer.swift` / `ROS2SchemaDefinitions.swift`). Unknown
/// schemas fall back to a byte-count row instead of throwing.
class Ros2MessageDecoder {
  const Ros2MessageDecoder._();

  /// Schemas rendered as playable JPEG frames.
  static const compressedImageSchema = "sensor_msgs/msg/CompressedImage";

  /// Schema rendered as a playable depth colormap.
  static const rawImageSchema = "sensor_msgs/msg/Image";


  static DecodedMcapMessage decode(String schemaName, Uint8List payload) {
    try {
      final cdr = CdrDeserializer(payload);
      switch (schemaName) {
        case compressedImageSchema:
          return _compressedImage(cdr);
        case rawImageSchema:
          return _image(cdr);
        case "geometry_msgs/msg/PoseStamped":
          return _poseStamped(cdr);
        case "sensor_msgs/msg/Imu":
          return _imu(cdr);
        case "sensor_msgs/msg/CameraInfo":
          return _cameraInfo(cdr);
        case "tf2_msgs/msg/TFMessage":
          return _tfMessage(cdr);
        case "nav_msgs/msg/Path":
          return _path(cdr);
        case "sensor_msgs/msg/PointCloud2":
          return _pointCloud2(cdr);
        case "visualization_msgs/msg/Marker":
          return _marker(cdr);
        case "stera/msg/TrackingState":
          return _trackingState(cdr);
        case "stera/msg/DeviceMetrics":
          return _deviceMetrics(cdr);
        case "stera/msg/ImuIntrinsics":
          return _imuIntrinsics(cdr);
        default:
          return _fallback(schemaName, payload);
      }
    } catch (e) {
      return DecodedMcapMessage(
        fields: [
          MapEntry("schema", schemaName),
          MapEntry("size", "${payload.length} bytes"),
          MapEntry("decode error", "$e"),
        ],
      );
    }
  }

  // -- std_msgs/Header ----------------------------------------------------

  static List<MapEntry<String, String>> _header(CdrDeserializer cdr) {
    final stampNs = cdr.timeNs();
    final frameId = cdr.string();
    return [
      MapEntry("stamp", _stamp(stampNs)),
      MapEntry("frame_id", frameId),
    ];
  }

  // -- Visual topics ------------------------------------------------------

  static DecodedMcapMessage _compressedImage(CdrDeserializer cdr) {
    final header = _header(cdr);
    final format = cdr.string();
    final data = cdr.byteSequence();
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("format", format),
        MapEntry("size", _bytes(data.length)),
      ],
      jpegBytes: format.toLowerCase().contains("jp") ? data : null,
    );
  }

  static DecodedMcapMessage _image(CdrDeserializer cdr) {
    final header = _header(cdr);
    final height = cdr.uint32();
    final width = cdr.uint32();
    final encoding = cdr.string();
    final isBigEndian = cdr.uint8() != 0;
    final step = cdr.uint32();
    final data = cdr.byteSequence();

    DecodedDepthFrame? depth;
    if (encoding == "16UC1" && !isBigEndian && data.length >= width * height * 2) {
      // Copy to an aligned buffer: sublist views of the payload may start on
      // an odd byte, which Uint16List.view rejects.
      final aligned = Uint8List.fromList(data);
      depth = DecodedDepthFrame(
        width: width,
        height: height,
        values: aligned.buffer.asUint16List(0, width * height),
      );
    }
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("resolution", "${width}x$height"),
        MapEntry("encoding", encoding),
        MapEntry("step", "$step"),
        MapEntry("size", _bytes(data.length)),
      ],
      depth: depth,
    );
  }

  // -- Geometry / sensors -------------------------------------------------

  static DecodedMcapMessage _poseStamped(CdrDeserializer cdr) {
    final header = _header(cdr);
    final x = cdr.float64();
    final y = cdr.float64();
    final z = cdr.float64();
    final qx = cdr.float64();
    final qy = cdr.float64();
    final qz = cdr.float64();
    final qw = cdr.float64();
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("position", _vec3(x, y, z)),
        MapEntry("orientation", _quat(qx, qy, qz, qw)),
      ],
      scene: Scene3D(
        poses: [Pose3D(x: x, y: y, z: z, qx: qx, qy: qy, qz: qz, qw: qw)],
      ),
    );
  }

  static DecodedMcapMessage _imu(CdrDeserializer cdr) {
    final header = _header(cdr);
    final q = cdr.float64List(4);
    final qCov = cdr.float64List(9);
    final av = cdr.float64List(3);
    final avCov = cdr.float64List(9);
    final la = cdr.float64List(3);
    final laCov = cdr.float64List(9);
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("orientation", _quat(q[0], q[1], q[2], q[3])),
        MapEntry("angular_velocity", "${_vec3(av[0], av[1], av[2])} rad/s"),
        MapEntry("linear_acceleration", "${_vec3(la[0], la[1], la[2])} m/s²"),
        MapEntry(
          "variances (q/ω/a)",
          "${_num(qCov[0])} / ${_num(avCov[0])} / ${_num(laCov[0])}",
        ),
      ],
    );
  }

  static DecodedMcapMessage _cameraInfo(CdrDeserializer cdr) {
    final header = _header(cdr);
    final height = cdr.uint32();
    final width = cdr.uint32();
    final distortionModel = cdr.string();
    final dCount = cdr.uint32();
    cdr.float64List(dCount);
    final k = cdr.float64List(9);
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("resolution", "${width}x$height"),
        MapEntry("distortion_model", distortionModel),
        MapEntry("fx / fy", "${_num(k[0])} / ${_num(k[4])}"),
        MapEntry("cx / cy", "${_num(k[2])} / ${_num(k[5])}"),
      ],
    );
  }

  static DecodedMcapMessage _tfMessage(CdrDeserializer cdr) {
    final count = cdr.uint32();
    final fields = <MapEntry<String, String>>[
      MapEntry("transforms", "$count"),
    ];
    // Compose chained transforms within the message (world → camera_link →
    // camera_optical_frame) so triads render in one consistent frame; a
    // parent that never appears as a child is treated as the world origin.
    final frames = <String, Pose3D>{};
    final poses = <Pose3D>[];
    for (var i = 0; i < count; i++) {
      cdr.timeNs();
      final frameId = cdr.string();
      final childFrameId = cdr.string();
      final t = cdr.float64List(3);
      final r = cdr.float64List(4);
      fields.add(
        MapEntry(
          "$frameId → $childFrameId",
          "t=${_vec3(t[0], t[1], t[2])}\nq=${_quat(r[0], r[1], r[2], r[3])}",
        ),
      );
      final parent = frames[frameId] ?? const Pose3D(x: 0, y: 0, z: 0);
      final child = parent.compose(
        Pose3D(
          x: t[0],
          y: t[1],
          z: t[2],
          qx: r[0],
          qy: r[1],
          qz: r[2],
          qw: r[3],
          label: childFrameId,
        ),
      );
      frames[childFrameId] = child;
      poses.add(child);
    }
    return DecodedMcapMessage(fields: fields, scene: Scene3D(poses: poses));
  }

  static DecodedMcapMessage _path(CdrDeserializer cdr) {
    final header = _header(cdr);
    final count = cdr.uint32();
    final polyline = Float32List(count * 3);
    Pose3D? lastPose;
    for (var i = 0; i < count; i++) {
      cdr.timeNs();
      cdr.string();
      final p = cdr.float64List(3);
      final q = cdr.float64List(4);
      polyline[i * 3] = p[0];
      polyline[i * 3 + 1] = p[1];
      polyline[i * 3 + 2] = p[2];
      if (i == count - 1) {
        lastPose = Pose3D(
          x: p[0],
          y: p[1],
          z: p[2],
          qx: q[0],
          qy: q[1],
          qz: q[2],
          qw: q[3],
        );
      }
    }
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("poses", "$count"),
        if (lastPose != null)
          MapEntry("latest position", _vec3(lastPose.x, lastPose.y, lastPose.z)),
      ],
      scene: count == 0
          ? null
          : Scene3D(
              polyline: polyline,
              poses: [?lastPose],
            ),
    );
  }

  /// Cap on rendered scatter points; larger clouds are stride-sampled.
  static const int _maxRenderPoints = 40000;

  static DecodedMcapMessage _pointCloud2(CdrDeserializer cdr) {
    final header = _header(cdr);
    final height = cdr.uint32();
    final width = cdr.uint32();
    final fieldCount = cdr.uint32();
    final names = <String>[];
    final offsets = <String, int>{};
    final datatypes = <String, int>{};
    for (var i = 0; i < fieldCount; i++) {
      final name = cdr.string();
      names.add(name);
      offsets[name] = cdr.uint32();
      datatypes[name] = cdr.uint8();
      cdr.uint32(); // count
    }
    cdr.uint8(); // is_bigendian
    final pointStep = cdr.uint32();
    cdr.uint32(); // row_step
    final data = cdr.byteSequence();

    final pointCount = height * width;
    Float32List? points;
    const float32Type = 7;
    final xOff = offsets["x"];
    final yOff = offsets["y"];
    final zOff = offsets["z"];
    if (pointCount > 0 &&
        xOff != null &&
        yOff != null &&
        zOff != null &&
        datatypes["x"] == float32Type &&
        data.length >= pointCount * pointStep) {
      final stride = (pointCount / _maxRenderPoints).ceil().clamp(1, 1 << 30);
      final sampled = (pointCount / stride).ceil();
      points = Float32List(sampled * 3);
      final view = ByteData.sublistView(data);
      var w = 0;
      for (var i = 0; i < pointCount; i += stride) {
        final base = i * pointStep;
        points[w++] = view.getFloat32(base + xOff, Endian.little);
        points[w++] = view.getFloat32(base + yOff, Endian.little);
        points[w++] = view.getFloat32(base + zOff, Endian.little);
      }
    }
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("points", "$pointCount"),
        MapEntry("fields", names.join(", ")),
        MapEntry("point_step", "$pointStep bytes"),
        MapEntry("size", _bytes(data.length)),
      ],
      scene: points == null ? null : Scene3D(points: points),
    );
  }

  /// Cap on rendered mesh triangles; larger meshes are stride-sampled.
  static const int _maxRenderTriangles = 12000;

  static DecodedMcapMessage _marker(CdrDeserializer cdr) {
    const triangleList = 11;
    final header = _header(cdr);
    final ns = cdr.string();
    final id = cdr.int32();
    final type = cdr.int32();
    cdr.int32(); // action
    final pose = cdr.float64List(7);
    cdr.float64List(3); // scale
    for (var i = 0; i < 4; i++) {
      cdr.float32(); // color
    }
    cdr.int32(); // lifetime sec
    cdr.uint32(); // lifetime nsec
    cdr.uint8(); // frame_locked
    final pointCount = cdr.uint32();

    Float32List? segments;
    if (pointCount > 0) {
      // Points are 3×float64 each, 8-aligned; after the first alignment the
      // stride is a clean 24 bytes.
      cdr.align(8);
      if (type == triangleList) {
        segments = _triangleWireframe(cdr, pointCount);
      } else {
        cdr.skip(pointCount * 24);
      }
    }
    final colorCount = cdr.uint32();
    cdr.skip(colorCount * 16);
    final text = cdr.string();

    final markerPose = Pose3D(
      x: pose[0],
      y: pose[1],
      z: pose[2],
      qx: pose[3],
      qy: pose[4],
      qz: pose[5],
      qw: pose[6],
      label: text.isNotEmpty ? text : (ns.isNotEmpty ? "$ns/$id" : null),
    );
    return DecodedMcapMessage(
      fields: [
        ...header,
        if (ns.isNotEmpty) MapEntry("ns", ns),
        MapEntry("id / type", "$id / ${_markerType(type)}"),
        MapEntry("position", _vec3(pose[0], pose[1], pose[2])),
        if (pointCount > 0) MapEntry("points", "$pointCount"),
        if (text.isNotEmpty) MapEntry("text", text),
      ],
      scene: segments != null
          ? Scene3D(lineSegments: segments)
          : Scene3D(poses: [markerPose]),
    );
  }

  /// Reads a TRIANGLE_LIST point array (3 vertices per triangle, 3×float64
  /// each) into wireframe edge segments, stride-sampling whole triangles when
  /// over the render cap. The cursor always ends past all [pointCount] points.
  static Float32List _triangleWireframe(CdrDeserializer cdr, int pointCount) {
    final triangleCount = pointCount ~/ 3;
    final stride =
        (triangleCount / _maxRenderTriangles).ceil().clamp(1, 1 << 30);
    final kept = triangleCount == 0 ? 0 : ((triangleCount / stride).ceil());
    // 3 edges per triangle × 2 endpoints × xyz
    final segments = Float32List(kept * 18);
    var w = 0;
    final v = List<double>.filled(9, 0);
    for (var t = 0; t < triangleCount; t++) {
      if (t % stride == 0 && w < segments.length) {
        for (var i = 0; i < 9; i++) {
          v[i] = cdr.float64();
        }
        // edges a-b, b-c, c-a
        for (final (from, to) in [(0, 1), (1, 2), (2, 0)]) {
          segments[w++] = v[from * 3];
          segments[w++] = v[from * 3 + 1];
          segments[w++] = v[from * 3 + 2];
          segments[w++] = v[to * 3];
          segments[w++] = v[to * 3 + 1];
          segments[w++] = v[to * 3 + 2];
        }
      } else {
        cdr.skip(72); // 9 float64s, already 8-aligned
      }
    }
    cdr.skip((pointCount - triangleCount * 3) * 24); // stray non-triple points
    return segments;
  }

  // -- custom messages ------------------------------------------------------

  static DecodedMcapMessage _trackingState(CdrDeserializer cdr) {
    final header = _header(cdr);
    final state = cdr.uint8();
    final reason = cdr.uint8();
    final stateStr = cdr.string();
    final reasonStr = cdr.string();
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("state", "$stateStr ($state)"),
        MapEntry("reason", "$reasonStr ($reason)"),
      ],
    );
  }

  static DecodedMcapMessage _deviceMetrics(CdrDeserializer cdr) {
    final header = _header(cdr);
    final batteryLevel = cdr.float32();
    cdr.uint8(); // battery_state
    final batteryStateStr = cdr.string();
    final cpuUsage = cdr.float32();
    final memUsed = cdr.float64();
    final memAvailable = cdr.float64();
    cdr.uint8(); // thermal_state
    final thermalStateStr = cdr.string();
    final deviceModel = cdr.string();
    return DecodedMcapMessage(
      fields: [
        ...header,
        // Writer stores percent already (RecordingHealthMonitor.swift:107).
        MapEntry("battery", "${batteryLevel.toStringAsFixed(0)}% ($batteryStateStr)"),
        MapEntry("cpu", "${cpuUsage.toStringAsFixed(1)}%"),
        MapEntry("memory", "${memUsed.toStringAsFixed(0)} / ${(memUsed + memAvailable).toStringAsFixed(0)} MB"),
        MapEntry("thermal", thermalStateStr),
        MapEntry("device", deviceModel),
      ],
    );
  }

  static DecodedMcapMessage _imuIntrinsics(CdrDeserializer cdr) {
    final header = _header(cdr);
    final accelNoise = cdr.float64();
    final gyroNoise = cdr.float64();
    final accelWalk = cdr.float64();
    final gyroWalk = cdr.float64();
    final accelBias = cdr.float64List(3);
    final gyroBias = cdr.float64List(3);
    final sampleRate = cdr.uint32();
    final source = cdr.string();
    return DecodedMcapMessage(
      fields: [
        ...header,
        MapEntry("accel noise / walk", "${_num(accelNoise)} / ${_num(accelWalk)}"),
        MapEntry("gyro noise / walk", "${_num(gyroNoise)} / ${_num(gyroWalk)}"),
        MapEntry("accel bias", _vec3(accelBias[0], accelBias[1], accelBias[2])),
        MapEntry("gyro bias", _vec3(gyroBias[0], gyroBias[1], gyroBias[2])),
        MapEntry("sample rate", "$sampleRate Hz"),
        MapEntry("source", source),
      ],
    );
  }

  static DecodedMcapMessage _fallback(String schemaName, Uint8List payload) {
    return DecodedMcapMessage(
      fields: [
        MapEntry("schema", schemaName),
        MapEntry("size", _bytes(payload.length)),
      ],
    );
  }

  // -- Formatting helpers ---------------------------------------------------

  static String _stamp(int ns) => "${(ns / 1e9).toStringAsFixed(3)} s";

  static String _num(double v) {
    final abs = v.abs();
    if (abs != 0 && (abs < 0.001 || abs >= 100000)) {
      return v.toStringAsExponential(3);
    }
    return v.toStringAsFixed(3);
  }

  static String _vec3(double x, double y, double z) =>
      "(${_num(x)}, ${_num(y)}, ${_num(z)})";

  static String _quat(double x, double y, double z, double w) =>
      "(${_num(x)}, ${_num(y)}, ${_num(z)}, ${_num(w)})";

  static String _bytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    final kb = bytes / 1024;
    if (kb < 1024) return "${kb.toStringAsFixed(1)} KB";
    return "${(kb / 1024).toStringAsFixed(2)} MB";
  }

  static String _markerType(int type) {
    switch (type) {
      case 2:
        return "SPHERE";
      case 9:
        return "TEXT_VIEW_FACING";
      case 11:
        return "TRIANGLE_LIST";
      default:
        return "type $type";
    }
  }
}
