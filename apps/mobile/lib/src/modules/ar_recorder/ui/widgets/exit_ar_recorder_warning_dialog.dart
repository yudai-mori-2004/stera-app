import "package:stera/src/core/common/widgets/app_confirmation_dialog.dart";
import "package:flutter/material.dart";

/// Shown when leaving the AR recorder while a recording session is active
/// (system back, swipe, or close control).
class ExitArRecorderWarningDialog extends StatelessWidget {
  const ExitArRecorderWarningDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppConfirmationDialog(
      title: "Discard recording?",
      message: "All recorded files in this session will be deleted.",
      cancelText: "Keep",
      confirmText: "Discard",
      isDestructive: true,
    );
  }
}
