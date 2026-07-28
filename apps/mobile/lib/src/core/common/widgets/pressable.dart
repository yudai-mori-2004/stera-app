import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:motor/motor.dart";

/// Wraps [child] with a spring-driven press-down scale effect.
///
/// Handles the tap gesture itself so the scale animation and the tap
/// callback stay in sync. When [enabled] is false the gesture is ignored
/// and no press effect plays.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.pressedScale = 0.96,
    this.motion = const CupertinoMotion.smooth(),
    this.behavior,
    this.hapticFeedback = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Long-press handler. Present so controls needing it can still use the
  /// app's press feel instead of dropping to a bare [GestureDetector].
  final VoidCallback? onLongPress;

  final bool enabled;

  /// Hit-test behavior for the underlying gesture detector. Pass
  /// [HitTestBehavior.opaque] when the child has transparent padding that must
  /// still be tappable; defaults to `deferToChild`.
  final HitTestBehavior? behavior;

  /// Scale applied while the pointer is down.
  final double pressedScale;

  /// Spring used to animate between resting and pressed scale.
  final Motion motion;

  /// Fires a light impact on press-down, so the tap is confirmed in the hand
  /// rather than only on screen. Disable for controls that emit their own
  /// haptic, or where a press isn't a discrete confirmation.
  final bool hapticFeedback;

  /// Announced by screen readers in place of [child]'s inferred label. Set it
  /// on icon-only controls, which otherwise announce as nothing.
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _isInteractive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTapDown() {
    if (widget.hapticFeedback) HapticFeedback.lightImpact();
    _setPressed(true);
  }

  @override
  Widget build(BuildContext context) {
    final result = GestureDetector(
      behavior: widget.behavior,
      onTap: _isInteractive ? widget.onTap : null,
      onLongPress: _isInteractive ? widget.onLongPress : null,
      onTapDown: _isInteractive ? (_) => _handleTapDown() : null,
      onTapUp: _isInteractive ? (_) => _setPressed(false) : null,
      onTapCancel: _isInteractive ? () => _setPressed(false) : null,
      child: SingleMotionBuilder(
        motion: widget.motion,
        value: _pressed ? widget.pressedScale : 1.0,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: widget.child,
      ),
    );

    if (widget.semanticLabel == null) return result;
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: _isInteractive,
      child: result,
    );
  }
}
