import "package:flutter/widgets.dart";
import "package:motor/motor.dart";

/// Springs [child] into view on first build: it settles from a slightly
/// smaller, lower, transparent state up to its resting position with a little
/// overshoot. Use to give modal sheets and dialogs an "alive" entrance instead
/// of the platform's flat slide.
///
/// The motion is driven by a single spring value 0 → 1; [child] is rebuilt
/// once per frame while it settles, then left untouched.
class SpringEntrance extends StatefulWidget {
  const SpringEntrance({
    super.key,
    required this.child,
    this.motion = const CupertinoMotion.bouncy(),
    this.beginScale = 0.92,
    this.beginOffset = const Offset(0, 24),
  });

  final Widget child;

  /// Spring used to carry the entrance from its begin state to rest.
  final Motion motion;

  /// Scale the child starts at before settling to 1.0.
  final double beginScale;

  /// Translation (logical px) the child starts at before settling to zero.
  final Offset beginOffset;

  @override
  State<SpringEntrance> createState() => _SpringEntranceState();
}

class _SpringEntranceState extends State<SpringEntrance> {
  // Starts at 0 (fully "entering"); flipped to 1 after the first frame so the
  // spring animates the transition rather than snapping.
  double _target = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _target = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: widget.motion,
      value: _target,
      child: widget.child,
      builder: (context, t, child) {
        final scale = widget.beginScale + (1.0 - widget.beginScale) * t;
        final offset = widget.beginOffset * (1.0 - t);
        return Opacity(
          // Clamp: a bouncy spring can overshoot past 1.0, which Opacity rejects.
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: offset,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}
