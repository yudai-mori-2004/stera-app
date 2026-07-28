enum UploadedVideosStatus { all, approved, pending, rejected, flagged }

extension UploadedVideosStatusExtension on UploadedVideosStatus {
  String get label {
    switch (this) {
      case UploadedVideosStatus.all:
        return "All";
      case UploadedVideosStatus.approved:
        return "Approved";
      case UploadedVideosStatus.pending:
        return "Pending";
      case UploadedVideosStatus.rejected:
        return "Rejected";
      case UploadedVideosStatus.flagged:
        return "Flagged";
    }
  }

  String get title {
    switch (this) {
      case UploadedVideosStatus.all:
        return "All Uploaded Videos";
      case UploadedVideosStatus.approved:
        return "Approved Videos";
      case UploadedVideosStatus.pending:
        return "Pending Videos";
      case UploadedVideosStatus.rejected:
        return "Rejected Videos";
      case UploadedVideosStatus.flagged:
        return "Flagged Videos";
    }
  }

  String get id {
    switch (this) {
      case UploadedVideosStatus.all:
        return "all";
      case UploadedVideosStatus.approved:
        return "approved";
      case UploadedVideosStatus.pending:
        return "pending";
      case UploadedVideosStatus.rejected:
        return "rejected";
      case UploadedVideosStatus.flagged:
        return "flagged";
    }
  }
}
