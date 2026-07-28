import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";

enum UploadStatus {
  notStarted,
  pending,
  uploading,
  completed,
  failed,
  cancelled,

  /// Individually paused by the user. Multipart state and progress are
  /// preserved; the queue skips it until the user resumes it. Survives app
  /// restarts (unlike the queue-level pause, which is in-memory only).
  paused,
}

extension UploadStatusExtension on UploadStatus {
  Color statusColor(BuildContext context) => switch (this) {
    UploadStatus.notStarted => context.colors.neutralDarkGray,
    UploadStatus.pending => context.colors.yellow,
    UploadStatus.uploading => context.colors.blue,
    UploadStatus.completed => context.colors.green,
    UploadStatus.failed => context.colors.textDestructive,
    UploadStatus.cancelled => context.colors.neutralGray,
    UploadStatus.paused => context.colors.textSecondary,
  };

  String get label {
    switch (this) {
      case UploadStatus.notStarted:
        return "PENDING";
      case UploadStatus.pending:
        return "QUEUED";
      case UploadStatus.uploading:
        return "UPLOADING";
      case UploadStatus.completed:
        return "COMPLETED";
      case UploadStatus.failed:
        return "FAILED";
      case UploadStatus.cancelled:
        return "CANCELLED";
      case UploadStatus.paused:
        return "PAUSED";
    }
  }
}
