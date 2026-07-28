import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";

class ProfileRepo {
  /// Feedback is out of scope for v1 (no `/feedback` route on the new server).
  static Future<Failure?> submitFeedback({
    required String comment,
  }) async {
    return Failure(
      code: ErrorType.notFound,
      message: "Feedback is not available in this build.",
    );
  }
}
