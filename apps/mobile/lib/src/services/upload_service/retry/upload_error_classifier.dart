import "dart:async";
import "dart:io";

import "package:stera/src/services/db/schema/enums/upload_error_category.dart";

/// Maps a raw failure — a native channel error code, an HTTP status, or a
/// thrown Dart exception — to exactly one [UploadErrorCategory]. The category,
/// not the raw error, drives retry policy (see [UploadRetryPolicy]).
abstract final class UploadErrorClassifier {
  /// Classify a failure. Prefer the most specific signal available: an explicit
  /// [nativeErrorCode] (the iOS window engine emits these), else an
  /// [httpStatus], else a thrown [error]. Falls back to the safest *retryable*
  /// category so an unrecognised blip is retried rather than dropped.
  static UploadErrorCategory classify({
    String? nativeErrorCode,
    int? httpStatus,
    Object? error,
  }) {
    if (nativeErrorCode != null) {
      final fromCode = fromNativeCode(nativeErrorCode);
      if (fromCode != null) return fromCode;
    }
    if (httpStatus != null) {
      final fromStatus = fromHttpStatus(httpStatus);
      if (fromStatus != null) return fromStatus;
    }
    if (error != null) return _fromException(error);
    return UploadErrorCategory.network;
  }

  /// Native channel error codes (07 §3) plus a few legacy Impl strings.
  static UploadErrorCategory? fromNativeCode(String code) {
    switch (code.trim().toLowerCase()) {
      case "timeout":
        return UploadErrorCategory.timeout;
      case "network":
      case "cancelled":
      case "userforcequit":
      case "user_force_quit":
        return UploadErrorCategory.network;
      case "urlexpired":
      case "url_expired":
        return UploadErrorCategory.urlExpired;
      case "fileerror":
      case "file_error":
      case "file_read_failed":
        return UploadErrorCategory.fileError;
      case "diskfull":
      case "disk_full":
      case "temp_file_write_failed":
        return UploadErrorCategory.diskFull;
      case "throttled":
      case "slowdown":
        return UploadErrorCategory.throttled;
      case "auth":
      case "auth_error":
        return UploadErrorCategory.authError;
      case "http_4xx":
        return UploadErrorCategory.clientError;
      case "http_5xx":
        return UploadErrorCategory.serverError;
      default:
        return null;
    }
  }

  /// HTTP status → category. Returns null for 2xx (not an error).
  ///
  /// 403 maps to [UploadErrorCategory.urlExpired]: for presigned-URL PUTs the
  /// dominant cause of a 403 is an expired signature, and the redesign's
  /// recovery is "demote + re-presign". A genuine permission 403 still
  /// terminates via the part's total-attempt cap / the session budget.
  static UploadErrorCategory? fromHttpStatus(int status) {
    if (status >= 200 && status < 300) return null;
    if (status == 401) return UploadErrorCategory.authError;
    if (status == 403) return UploadErrorCategory.urlExpired;
    if (status == 429) return UploadErrorCategory.throttled;
    if (status >= 500) return UploadErrorCategory.serverError;
    if (status >= 400) return UploadErrorCategory.clientError;
    return UploadErrorCategory.network;
  }

  static UploadErrorCategory _fromException(Object error) {
    if (error is TimeoutException) return UploadErrorCategory.timeout;
    if (error is SocketException) return UploadErrorCategory.network;
    if (error is FileSystemException) {
      final message = (error.osError?.message ?? error.message).toLowerCase();
      if (message.contains("no space") || message.contains("enospc")) {
        return UploadErrorCategory.diskFull;
      }
      return UploadErrorCategory.fileError;
    }
    if (error is HttpException) return UploadErrorCategory.network;
    return UploadErrorCategory.network;
  }
}
