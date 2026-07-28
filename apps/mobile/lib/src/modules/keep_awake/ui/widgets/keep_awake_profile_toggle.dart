import "package:stera/src/core/common/widgets/toggle_row.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/keep_awake/helpers/keep_awake_controller.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

/// Profile settings row that keeps the screen awake independently of uploads.
class KeepAwakeProfileToggle extends StatelessWidget {
  const KeepAwakeProfileToggle({super.key});

  void _onChanged(bool on) {
    HapticFeedback.lightImpact();
    KeepAwakeController.setEnabled(on);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: KeepAwakeController.enabled,
      builder: (context, on, _) {
        return ToggleRow(
          title: "Keep screen on",
          subtitle: "Prevent the screen from sleeping while the app is open.",
          value: on,
          onChanged: _onChanged,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
        );
      },
    );
  }
}
