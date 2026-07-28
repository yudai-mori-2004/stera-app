import "dart:typed_data";

/// A position + orientation in world space (ROS/ARKit right-handed).
class Pose3D {
  final double x;
  final double y;
  final double z;
  final double qx;
  final double qy;
  final double qz;
  final double qw;

  /// Optional display label (frame id, marker text…).
  final String? label;

  const Pose3D({
    required this.x,
    required this.y,
    required this.z,
    this.qx = 0,
    this.qy = 0,
    this.qz = 0,
    this.qw = 1,
    this.label,
  });

  /// Rotates a local-frame vector into world frame:
  /// v' = v + 2·q⃗ × (q⃗ × v + w·v).
  (double, double, double) rotate(double vx, double vy, double vz) {
    final tx = 2 * (qy * vz - qz * vy);
    final ty = 2 * (qz * vx - qx * vz);
    final tz = 2 * (qx * vy - qy * vx);
    return (
      vx + qw * tx + (qy * tz - qz * ty),
      vy + qw * ty + (qz * tx - qx * tz),
      vz + qw * tz + (qx * ty - qy * tx),
    );
  }

  /// this ∘ child: the pose of [child] expressed in this pose's parent frame.
  Pose3D compose(Pose3D child) {
    final (cx, cy, cz) = rotate(child.x, child.y, child.z);
    // Hamilton product q = this.q * child.q
    return Pose3D(
      x: x + cx,
      y: y + cy,
      z: z + cz,
      qx: qw * child.qx + qx * child.qw + qy * child.qz - qz * child.qy,
      qy: qw * child.qy - qx * child.qz + qy * child.qw + qz * child.qx,
      qz: qw * child.qz + qx * child.qy - qy * child.qx + qz * child.qw,
      qw: qw * child.qw - qx * child.qx - qy * child.qy - qz * child.qz,
      label: child.label,
    );
  }
}

/// Renderable 3D geometry decoded from one message: any combination of a
/// point set, a connected strip, wireframe segments, and oriented poses.
/// All coordinate arrays are packed xyz triples.
class Scene3D {
  /// Scatter points (point clouds).
  final Float32List? points;

  /// A connected polyline strip (trajectory / path).
  final Float32List? polyline;

  /// Independent line segments, two consecutive xyz triples per segment
  /// (mesh wireframe).
  final Float32List? lineSegments;

  /// Oriented poses drawn as RGB axis triads.
  final List<Pose3D> poses;

  const Scene3D({
    this.points,
    this.polyline,
    this.lineSegments,
    this.poses = const [],
  });

  bool get isEmpty =>
      (points == null || points!.isEmpty) &&
      (polyline == null || polyline!.isEmpty) &&
      (lineSegments == null || lineSegments!.isEmpty) &&
      poses.isEmpty;
}
