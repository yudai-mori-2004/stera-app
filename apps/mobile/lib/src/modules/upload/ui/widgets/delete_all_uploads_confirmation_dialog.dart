import "package:stera/src/core/common/widgets/app_confirmation_dialog.dart";
import "package:flutter/material.dart";

/// Confirms deleting every active upload. Like the per-upload "Delete", this
/// stops any upload in progress and permanently removes the local recordings.
class DeleteAllUploadsConfirmationDialog extends StatelessWidget {
  const DeleteAllUploadsConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppConfirmationDialog(
      title: "Delete all videos?",
      message:
          "This will stop any upload in progress and permanently delete the "
          "local recordings from this device. This can't be undone.",
      cancelText: "Keep",
      confirmText: "Delete all",
      isDestructive: true,
    );
  }
}
