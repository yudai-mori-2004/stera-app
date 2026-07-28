import "package:stera/src/core/common/widgets/app_confirmation_dialog.dart";
import "package:flutter/material.dart";

class RemoveQueuedUploadConfirmationDialog extends StatelessWidget {
  const RemoveQueuedUploadConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppConfirmationDialog(
      title: "Delete this video?",
      message:
          "This will stop any upload in progress and permanently delete the local recording from this device. This can't be undone.",
      cancelText: "Keep",
      confirmText: "Delete",
      isDestructive: true,
    );
  }
}
