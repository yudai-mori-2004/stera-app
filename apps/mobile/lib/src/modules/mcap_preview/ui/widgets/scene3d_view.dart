import "dart:math" as math;
import "dart:typed_data";
import "dart:ui" show PointMode;

import "package:flutter/material.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/services/mcap_reader/cdr/scene3d.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_type.dart";

/// Orbitable 3D viewport for decoded MCAP geometry: point clouds, mesh
/// wireframes, trajectories and pose triads, plus an optional playback trail
/// split at the playhead into visited / upcoming.
///
/// One-finger drag orbits, two-finger pinch zooms and pans, double-tap
/// resets the camera. Rendering is a plain orthographic CustomPainter — no
/// GL, no dependencies.
class Scene3DView extends StatefulWidget {
  const Scene3DView({
    super.key,
    required this.scene,
    this.trailPositions,
    this.trailTimesNs,
    this.playheadNs = 0,
  });

  final Scene3D? scene;
  final Float32List? trailPositions;
  final Int64List? trailTimesNs;
  final int playheadNs;

  @override
  State<Scene3DView> createState() => _Scene3DViewState();
}

class _Scene3DViewState extends State<Scene3DView> {
  static const double _initialYaw = -0.7;
  static const double _initialPitch = 0.45;

  double _yaw = _initialYaw;
  double _pitch = _initialPitch;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _lastScale = 1;

  // Fitted bounds, cached per data identity so a static mesh isn't re-scanned
  // every frame while a moving pose still refits as its trail streams in.
  _Bounds? _bounds;
  int _boundsKey = 0;

  _Bounds _fittedBounds() {
    final key = Object.hash(
      identityHashCode(widget.scene),
      identityHashCode(widget.trailPositions),
    );
    if (_bounds != null && key == _boundsKey) return _bounds!;
    final b = _Bounds();
    final scene = widget.scene;
    if (scene != null) {
      b.addTriples(scene.points);
      b.addTriples(scene.polyline);
      b.addTriples(scene.lineSegments);
      for (final p in scene.poses) {
        b.add(p.x, p.y, p.z);
      }
    }
    b.addTriples(widget.trailPositions);
    _bounds = b;
    _boundsKey = key;
    return b;
  }

  void _reset() {
    setState(() {
      _yaw = _initialYaw;
      _pitch = _initialPitch;
      _zoom = 1;
      _pan = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onDoubleTap: _reset,
      onScaleStart: (_) => _lastScale = 1,
      onScaleUpdate: (details) {
        setState(() {
          if (details.pointerCount <= 1) {
            _yaw += details.focalPointDelta.dx * 0.01;
            _pitch = (_pitch + details.focalPointDelta.dy * 0.01)
                .clamp(-1.55, 1.55);
          } else {
            final delta = details.scale / _lastScale;
            _lastScale = details.scale;
            _zoom = (_zoom * delta).clamp(0.05, 100);
            _pan += details.focalPointDelta;
          }
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.smPlus),
        child: Container(
          color: colors.surfaceBlack,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _Scene3DPainter(
                  scene: widget.scene,
                  trailPositions: widget.trailPositions,
                  trailTimesNs: widget.trailTimesNs,
                  playheadNs: widget.playheadNs,
                  bounds: _fittedBounds(),
                  yaw: _yaw,
                  pitch: _pitch,
                  zoom: _zoom,
                  pan: _pan,
                  accent: colors.blue,
                  chrome: colors.neutralWhite,
                  axisX: colors.red,
                  axisY: colors.green,
                  axisZ: colors.blue,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 8,
                child: Text(
                  "drag to orbit • pinch to zoom",
                  style: context.textTheme.bodyXs.copyWith(
                    color: context.colors.neutralWhite.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bounds {
  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = -double.infinity,
      maxY = -double.infinity,
      maxZ = -double.infinity;
  bool get isEmpty => minX > maxX;

  void add(double x, double y, double z) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }

  void addTriples(Float32List? triples) {
    if (triples == null) return;
    for (var i = 0; i + 2 < triples.length; i += 3) {
      add(triples[i], triples[i + 1], triples[i + 2]);
    }
  }

  double get centerX => isEmpty ? 0 : (minX + maxX) / 2;
  double get centerY => isEmpty ? 0 : (minY + maxY) / 2;
  double get centerZ => isEmpty ? 0 : (minZ + maxZ) / 2;

  /// Half-extent of the largest dimension, floored so a single pose still
  /// gets a usable room-scale viewport.
  double get radius {
    if (isEmpty) return 1;
    final r = [maxX - minX, maxY - minY, maxZ - minZ]
            .reduce(math.max) /
        2;
    return math.max(r, 0.5);
  }
}

class _Scene3DPainter extends CustomPainter {
  _Scene3DPainter({
    required this.scene,
    required this.trailPositions,
    required this.trailTimesNs,
    required this.playheadNs,
    required this.bounds,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
    required this.accent,
    required this.chrome,
    required this.axisX,
    required this.axisY,
    required this.axisZ,
  });

  final Scene3D? scene;
  final Float32List? trailPositions;
  final Int64List? trailTimesNs;
  final int playheadNs;
  final _Bounds bounds;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset pan;
  final Color accent;

  /// Grid, trail-ahead, labels and pose dots. The scene sits on
  /// `surfaceBlack` in both themes, so this comes from the palette's white
  /// anchor rather than from `Colors.white` — a fork that repaints its
  /// anchors repaints the viewport with them.
  final Color chrome;

  /// The world axes. Semantic rather than decorative (X red, Y green, Z blue
  /// is the convention every robotics tool uses), so they take the palette's
  /// semantic colours rather than the brand accent.
  final Color axisX;
  final Color axisY;
  final Color axisZ;

  late final double _cy = math.cos(yaw);
  late final double _sy = math.sin(yaw);
  late final double _cp = math.cos(pitch);
  late final double _sp = math.sin(pitch);
  late double _scale;
  late Offset _origin;

  Offset _project(double x, double y, double z) {
    final dx = x - bounds.centerX;
    final dy = y - bounds.centerY;
    final dz = z - bounds.centerZ;
    // Yaw around the world Y (up) axis, then pitch around the view X axis.
    final rx = dx * _cy + dz * _sy;
    final rz = -dx * _sy + dz * _cy;
    final ry = dy * _cp - rz * _sp;
    return Offset(_origin.dx + rx * _scale, _origin.dy - ry * _scale);
  }

  Float32List _projectTriples(Float32List triples) {
    final out = Float32List((triples.length ~/ 3) * 2);
    var w = 0;
    for (var i = 0; i + 2 < triples.length; i += 3) {
      final p = _project(triples[i], triples[i + 1], triples[i + 2]);
      out[w++] = p.dx;
      out[w++] = p.dy;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _scale = 0.42 * math.min(size.width, size.height) / bounds.radius * zoom;
    _origin = size.center(Offset.zero) + pan;

    _paintGrid(canvas);
    _paintOriginAxes(canvas);

    final scene = this.scene;

    // Full-recording trail, split at the playhead.
    final trail = trailPositions;
    final times = trailTimesNs;
    if (trail != null && times != null && times.isNotEmpty) {
      final visitedCount = _countAtOrBefore(times, playheadNs);
      final projected = _projectTriples(trail);
      if (visitedCount > 1) {
        canvas.drawRawPoints(
          PointMode.polygon,
          Float32List.sublistView(projected, 0, visitedCount * 2),
          Paint()
            ..color = accent
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
      if (visitedCount < times.length) {
        final from = math.max(0, (visitedCount - 1) * 2);
        canvas.drawRawPoints(
          PointMode.polygon,
          Float32List.sublistView(projected, from),
          Paint()
            ..color = chrome.withValues(alpha: 0.18)
            ..strokeWidth = 1.5,
        );
      }
    }

    if (scene != null) {
      final segments = scene.lineSegments;
      if (segments != null && segments.isNotEmpty) {
        canvas.drawRawPoints(
          PointMode.lines,
          _projectTriples(segments),
          Paint()
            ..color = chrome.withValues(alpha: 0.35)
            ..strokeWidth = 1,
        );
      }
      final polyline = scene.polyline;
      if (polyline != null && polyline.length >= 6) {
        canvas.drawRawPoints(
          PointMode.polygon,
          _projectTriples(polyline),
          Paint()
            ..color = accent
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
      final points = scene.points;
      if (points != null && points.isNotEmpty) {
        canvas.drawRawPoints(
          PointMode.points,
          _projectTriples(points),
          Paint()
            ..color = accent.withValues(alpha: 0.85)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
      var labelBudget = 8;
      for (final pose in scene.poses) {
        _paintPoseTriad(canvas, pose);
        if (pose.label != null && labelBudget > 0) {
          labelBudget--;
          _paintLabel(canvas, pose);
        }
      }
    }
  }

  void _paintGrid(Canvas canvas) {
    final r = bounds.radius;
    // A nice round step: ~8 cells across the scene.
    final rawStep = r / 4;
    final magnitude = math.pow(10, (math.log(rawStep) / math.ln10).floor());
    final step = (rawStep / magnitude).round().clamp(1, 5) * magnitude.toDouble();
    final paint = Paint()
      ..color = chrome.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    // Ground plane (y = 0, gravity-aligned world) around the scene center.
    final cx = (bounds.centerX / step).round() * step;
    final cz = (bounds.centerZ / step).round() * step;
    const cells = 5;
    for (var i = -cells; i <= cells; i++) {
      canvas.drawLine(
        _project(cx + i * step, 0, cz - cells * step),
        _project(cx + i * step, 0, cz + cells * step),
        paint,
      );
      canvas.drawLine(
        _project(cx - cells * step, 0, cz + i * step),
        _project(cx + cells * step, 0, cz + i * step),
        paint,
      );
    }
  }

  void _paintOriginAxes(Canvas canvas) {
    final len = bounds.radius * 0.25;
    final o = _project(0, 0, 0);
    canvas.drawLine(o, _project(len, 0, 0), _axisPaint(axisX));
    canvas.drawLine(o, _project(0, len, 0), _axisPaint(axisY));
    canvas.drawLine(o, _project(0, 0, len), _axisPaint(axisZ));
  }

  void _paintPoseTriad(Canvas canvas, Pose3D pose) {
    final len = (bounds.radius * 0.12).clamp(0.05, 1.0);
    final o = _project(pose.x, pose.y, pose.z);
    final (xx, xy, xz) = pose.rotate(len, 0, 0);
    final (yx, yy, yz) = pose.rotate(0, len, 0);
    final (zx, zy, zz) = pose.rotate(0, 0, len);
    canvas.drawLine(
      o,
      _project(pose.x + xx, pose.y + xy, pose.z + xz),
      _axisPaint(axisX),
    );
    canvas.drawLine(
      o,
      _project(pose.x + yx, pose.y + yy, pose.z + yz),
      _axisPaint(axisY),
    );
    canvas.drawLine(
      o,
      _project(pose.x + zx, pose.y + zy, pose.z + zz),
      _axisPaint(axisZ),
    );
    canvas.drawCircle(o, 3, Paint()..color = chrome);
  }

  void _paintLabel(Canvas canvas, Pose3D pose) {
    final painter = TextPainter(
      text: TextSpan(
        text: pose.label,
        style: TextStyle(
          color: chrome.withValues(alpha: 0.7),
          fontSize: AppType.xs,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: 140);
    final o = _project(pose.x, pose.y, pose.z);
    painter.paint(canvas, o + const Offset(6, -14));
  }

  Paint _axisPaint(Color color) => Paint()
    ..color = color
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  static int _countAtOrBefore(Int64List times, int timeNs) {
    var lo = 0;
    var hi = times.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (times[mid] <= timeNs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  bool shouldRepaint(covariant _Scene3DPainter old) {
    return old.scene != scene ||
        old.trailPositions != trailPositions ||
        old.playheadNs != playheadNs ||
        old.yaw != yaw ||
        old.pitch != pitch ||
        old.zoom != zoom ||
        old.pan != pan ||
        old.accent != accent ||
        old.chrome != chrome ||
        old.axisX != axisX ||
        old.axisY != axisY ||
        old.axisZ != axisZ;
  }
}
