import "package:stera/src/core/common/widgets/app_confirmation_dialog.dart";
import "package:flutter/material.dart";

/// Confirms cancelling every active upload. Like the per-upload "Cancel
/// upload", this resets the videos to their ready-to-upload state and keeps the
/// local recordings on the device.
class CancelAllUploadsConfirmationDialog extends StatelessWidget {
  const CancelAllUploadsConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppConfirmationDialog(
      title: "Cancel all uploads?",
      message:
          "This will stop every upload and reset the videos to their "
          "ready-to-upload state. Your local recordings stay on this device.",
      cancelText: "Keep uploading",
      confirmText: "Cancel all",
    );
  }
}
