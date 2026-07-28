import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";
import "package:motor/motor.dart";

/// Styled [Switch] used in settings panels (AR recording, keep awake, etc.).
///
/// On top of the native thumb slide, the whole control springs with a small
/// bouncy scale overshoot each time it flips, so toggling feels alive.
class AppToggleSwitch extends StatelessWidget {
  const AppToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.scale = 0.92,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double scale;

  @override
  Widget build(BuildContext context) {
    // Springs between the resting scale (off) and a hair larger (on); the
    // bouncy motion overshoots on each transition for a satisfying snap.
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: value ? 1.0 : 0.0,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: context.colors.green,
        activeTrackColor: context.colors.green.withValues(alpha: 0.28),
        inactiveThumbColor: context.colors.neutralDarkGray,
        inactiveTrackColor: context.colors.neutralLightGray,
      ),
      builder: (context, t, child) {
        return Transform.scale(scale: scale + 0.06 * t, child: child);
      },
    );
  }
}
