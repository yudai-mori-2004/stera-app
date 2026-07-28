import "dart:math" as math;

import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

/// Coaching overlay shown during AR sensor initialization.
/// Displays an animated phone on a perspective grid, similar to
/// Apple's ARKit coaching view, with "Move iPhone to start" text.
class ArCoachingOverlay extends StatefulWidget {
  const ArCoachingOverlay({super.key});

  @override
  State<ArCoachingOverlay> createState() => _ArCoachingOverlayState();
}

class _ArCoachingOverlayState extends State<ArCoachingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _bobController;
  late final AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _bobController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_bobController, _dotController]),
            builder: (context, _) {
              return CustomPaint(
                size: const Size(280, 180),
                painter: _CoachingPainter(
                  bobValue: _bobController.value,
                  dotValue: _dotController.value,
                  chrome: context.darkColors.neutralWhite,
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            "Move your phone slowly to start recording.",
            style: context.darkTextTheme.headMd.copyWith(
              color: context.darkColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachingPainter extends CustomPainter {
  final double bobValue;
  final double dotValue;

  /// The overlay sits on the camera feed, so its chrome is always the dark
  /// palette's white anchor rather than `Colors.white` — the same source the
  /// caption above it reads from, and one a fork can repaint.
  final Color chrome;

  _CoachingPainter({
    required this.bobValue,
    required this.dotValue,
    required this.chrome,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // --- Perspective plane (trapezoid) ---
    final planePaint = Paint()
      ..color = chrome.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Trapezoid: narrower top, wider bottom
    const topWidth = 180.0;
    const bottomWidth = 260.0;
    const planeTop = 40.0;
    const planeBottom = 150.0;

    final topLeft = Offset(centerX - topWidth / 2, planeTop);
    final topRight = Offset(centerX + topWidth / 2, planeTop);
    final bottomRight = Offset(centerX + bottomWidth / 2, planeBottom);
    final bottomLeft = Offset(centerX - bottomWidth / 2, planeBottom);

    final planePath = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();

    canvas.drawPath(planePath, planePaint);

    // --- Grid dots on the plane ---
    const rows = 3;
    const cols = 4;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // Interpolate position on the trapezoid
        final rowT = (r + 1) / (rows + 1); // 0..1 within plane height
        final colT = (c + 1) / (cols + 1); // 0..1 within row width

        final y = planeTop + (planeBottom - planeTop) * rowT;
        // Width at this row (linear interpolation between top and bottom widths)
        final widthAtRow = topWidth + (bottomWidth - topWidth) * rowT;
        final rowLeft = centerX - widthAtRow / 2;
        final x = rowLeft + widthAtRow * colT;

        // Pulsing opacity based on dot index
        final dotIndex = r * cols + c;
        final totalDots = rows * cols;
        final phase = (dotValue - dotIndex / totalDots) % 1.0;
        final opacity = 0.2 + 0.6 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));

        final dotPaint = Paint()
          ..color = chrome.withValues(alpha: opacity)
          ..style = PaintingStyle.fill;

        final dotRadius = 2.0 + 1.0 * rowT; // slightly larger toward bottom
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }

    // --- Phone outline ---
    final bobOffset = math.sin(bobValue * 2 * math.pi) * 6;
    final tiltAngle = math.sin((bobValue * 2 * math.pi) + math.pi / 3) * 0.08;

    const phoneWidth = 64.0;
    const phoneHeight = 36.0;
    final phoneX = centerX - phoneWidth / 2;
    final phoneY = centerY - phoneHeight / 2 - 10 + bobOffset;

    canvas.save();
    canvas.translate(centerX, phoneY + phoneHeight / 2);
    canvas.rotate(tiltAngle);
    canvas.translate(-centerX, -(phoneY + phoneHeight / 2));

    // Phone body
    final phonePaint = Paint()
      ..color = chrome.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(phoneX, phoneY, phoneWidth, phoneHeight),
      const Radius.circular(AppRadii.xsPlus),
    );
    canvas.drawRRect(phoneRect, phonePaint);

    // Screen area (slightly inset, filled)
    final screenPaint = Paint()
      ..color = chrome.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final screenRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(phoneX + 8, phoneY + 3, phoneWidth - 14, phoneHeight - 6),
      const Radius.circular(AppRadii.xs),
    );
    canvas.drawRRect(screenRect, screenPaint);

    // Camera notch (on the left side for landscape)
    final notchPaint = Paint()
      ..color = chrome.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(phoneX + 5, phoneY + phoneHeight / 2),
      2.0,
      notchPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoachingPainter oldDelegate) {
    return oldDelegate.bobValue != bobValue ||
        oldDelegate.dotValue != dotValue ||
        oldDelegate.chrome != chrome;
  }
}
