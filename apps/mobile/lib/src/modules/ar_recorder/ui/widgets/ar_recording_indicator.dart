import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";

/// Minimal REC-style indicator: blinks while actively recording, solid when paused.
class ArRecordingIndicator extends StatefulWidget {
  const ArRecordingIndicator({
    super.key,
    required this.isRecording,
    required this.isPaused,
  });

  final bool isRecording;
  final bool isPaused;

  @override
  State<ArRecordingIndicator> createState() => _ArRecordingIndicatorState();
}

class _ArRecordingIndicatorState extends State<ArRecordingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    if (widget.isRecording && !widget.isPaused) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ArRecordingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldBlink = widget.isRecording && !widget.isPaused;
    final wasBlinking = oldWidget.isRecording && !oldWidget.isPaused;
    if (shouldBlink && !wasBlinking) {
      _controller.repeat(reverse: true);
    } else if (!shouldBlink && wasBlinking) {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRecording && !widget.isPaused) {
      return const SizedBox.shrink();
    }

    final red = context.colors.red;
    const size = 12.0;

    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: red.withValues(alpha: 0.55),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
    );

    if (widget.isPaused) {
      return dot;
    }

    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.4,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: dot,
    );
  }
}
