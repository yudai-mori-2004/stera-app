import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";

class DottedLinePainter extends CustomPainter {
  final Color lineColor;

  DottedLinePainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(DottedLinePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}

class DottedLine extends StatelessWidget {
  final Color? color;

  const DottedLine({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: DottedLinePainter(
        lineColor: color ?? context.colors.textSecondary,
      ),
    );
  }
}
