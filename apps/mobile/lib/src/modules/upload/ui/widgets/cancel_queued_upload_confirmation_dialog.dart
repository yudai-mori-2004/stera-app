import "package:stera/src/core/common/widgets/app_confirmation_dialog.dart";
import "package:flutter/material.dart";

class CancelQueuedUploadConfirmationDialog extends StatelessWidget {
  const CancelQueuedUploadConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppConfirmationDialog(
      title: "Cancel upload?",
      message:
          "This will stop the upload and reset the video to its ready-to-upload state. Your local recording will stay on this device.",
      cancelText: "Keep uploading",
      confirmText: "Cancel upload",
    );
  }
}
