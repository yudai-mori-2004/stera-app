enum ErrorType {
  unknown,
  network,
  serviceUnavailable,
  unauthorized,
  invalidToken,
  notFound,
  badRequest,
  tooManyRequests,
  validation,
  duplicateUpload,
  cancelled,
  paused,
  uploadInComplete,
  fileNotFound,
  maxRetriesExceeded,
  forbidden,
  conflict,
  insufficientStorage,
  processingFailed,
  unsupported,
}

extension ErrorCode on ErrorType {
  String get code {
    switch (this) {
      case ErrorType.unknown:
        return "ERROR_UNKNOWN";
      case ErrorType.network:
        return "ERROR_NETWORK";
      case ErrorType.serviceUnavailable:
        return "ERROR_SERVICE_UNAVAILABLE";
      case ErrorType.unauthorized:
        return "ERROR_UNAUTHORIZED";
      case ErrorType.invalidToken:
        return "ERROR_INVALID_TOKEN";
      case ErrorType.notFound:
        return "ERROR_NOT_FOUND";
      case ErrorType.badRequest:
        return "ERROR_BAD_REQUEST";
      case ErrorType.tooManyRequests:
        return "ERROR_TOO_MANY_REQUESTS";
      case ErrorType.validation:
        return "ERROR_VALIDATION";
      case ErrorType.duplicateUpload:
        return "ERROR_DUPLICATE_UPLOAD";
      case ErrorType.cancelled:
        return "ERROR_CANCELLED";
      case ErrorType.paused:
        return "ERROR_PAUSED";
      case ErrorType.uploadInComplete:
        return "ERROR_UPLOAD_INCOMPLETE";
      case ErrorType.fileNotFound:
        return "ERROR_FILE_NOT_FOUND";
      case ErrorType.maxRetriesExceeded:
        return "ERROR_MAX_RETRIES_EXCEEDED";
      case ErrorType.forbidden:
        return "ERROR_FORBIDDEN";
      case ErrorType.conflict:
        return "ERROR_CONFLICT";
      case ErrorType.insufficientStorage:
        return "ERROR_INSUFFICIENT_STORAGE";
      case ErrorType.processingFailed:
        return "ERROR_PROCESSING_FAILED";
      case ErrorType.unsupported:
        return "ERROR_UNSUPPORTED";
    }
  }

  String get message {
    switch (this) {
      case ErrorType.unknown:
        return "An unknown error occurred.";
      case ErrorType.network:
        return "A network error occurred. Please check your connection.";
      case ErrorType.serviceUnavailable:
        return "Sign-in is temporarily unavailable. Please try again in a moment.";
      case ErrorType.unauthorized:
        return "You are not authorized to perform this action.";
      case ErrorType.invalidToken:
        return "The provided token is invalid or has expired.";
      case ErrorType.notFound:
        return "The requested resource was not found.";
      case ErrorType.badRequest:
        return "The request was invalid or malformed.";
      case ErrorType.tooManyRequests:
        return "Too many requests have been made in a short period. Please try again later.";
      case ErrorType.validation:
        return "There was a validation error with the provided data.";
      case ErrorType.duplicateUpload:
        return "This upload already exists.";
      case ErrorType.cancelled:
        return "The operation was cancelled by the user.";
      case ErrorType.paused:
        return "The upload was paused by the user.";
      case ErrorType.uploadInComplete:
        return "The upload was not completed successfully.";
      case ErrorType.fileNotFound:
        return "The file was not found or access was denied.";
      case ErrorType.maxRetriesExceeded:
        return "The upload failed after maximum retry attempts.";
      case ErrorType.forbidden:
        return "You are not authorized to perform this action.";
      case ErrorType.conflict:
        return "A conflict occurred while performing the action.";
      case ErrorType.insufficientStorage:
        return "Not enough free storage on this device to continue the upload. Free up space and try again.";
      case ErrorType.processingFailed:
        return "Processing the recording failed. Please try again.";
      case ErrorType.unsupported:
        return "This feature is not supported on this device.";
    }
  }
}
