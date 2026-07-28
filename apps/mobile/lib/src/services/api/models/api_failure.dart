import "dart:developer" as dev;

import "package:flutter/foundation.dart";

import "package:stera/src/services/api/enums/error_type.dart";

class Failure {
  final ErrorType code;
  final String message;

  Failure({
    required this.code,
    this.message = "An unexpected error occurred. Please try again later.",
  });

  /// Creates a Failure from an exception, logging the full error but only
  /// exposing a safe user-facing message in release builds.
  /// In debug mode, the full error is shown for easier debugging.
  factory Failure.fromException(Object error, {ErrorType code = ErrorType.unknown}) {
    dev.log("Failure.fromException: $error");
    return Failure(
      code: code,
      message: kDebugMode ? error.toString() : code.message,
    );
  }

  Map<String, dynamic> toMap() => {"error": code.code, "message": message};

  factory Failure.fromMap(Map<String, dynamic> map) {
    return Failure(
      code: ErrorType.values.firstWhere(
        (element) => element.message == map["errorType"],
        orElse: () => ErrorType.unknown,
      ),
      message: map["message"] as String,
    );
  }

  factory Failure.unAuthorized() => Failure(
    code: ErrorType.unauthorized,
    message: ErrorType.unauthorized.message,
  );

  factory Failure.unknown() =>
      Failure(code: ErrorType.unknown, message: ErrorType.unknown.message);

  factory Failure.networkError() =>
      Failure(code: ErrorType.network, message: ErrorType.network.message);

  factory Failure.serviceUnavailable() => Failure(
    code: ErrorType.serviceUnavailable,
    message: ErrorType.serviceUnavailable.message,
  );

  factory Failure.notFound() =>
      Failure(code: ErrorType.notFound, message: ErrorType.notFound.message);

  factory Failure.tooManyRequests() => Failure(
    code: ErrorType.tooManyRequests,
    message: ErrorType.tooManyRequests.message,
  );

  factory Failure.forbidden() =>
      Failure(code: ErrorType.forbidden, message: ErrorType.forbidden.message);
}
