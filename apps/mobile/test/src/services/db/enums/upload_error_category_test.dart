import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/schema/enums/upload_error_category.dart";

void main() {
  group("UploadErrorCategory.isRetryable", () {
    test("transient categories are retryable", () {
      for (final c in [
        UploadErrorCategory.network,
        UploadErrorCategory.timeout,
        UploadErrorCategory.urlExpired,
        UploadErrorCategory.serverError,
        UploadErrorCategory.throttled,
        UploadErrorCategory.authError,
        UploadErrorCategory.diskFull,
      ]) {
        expect(c.isRetryable, isTrue, reason: "$c should be retryable");
      }
    });

    test("client and file errors are terminal by base policy", () {
      expect(UploadErrorCategory.clientError.isRetryable, isFalse);
      expect(UploadErrorCategory.fileError.isRetryable, isFalse);
    });
  });

  test("only urlExpired is exempt from the attempt budget", () {
    expect(UploadErrorCategory.urlExpired.countsAgainstAttemptBudget, isFalse);
    expect(UploadErrorCategory.network.countsAgainstAttemptBudget, isTrue);
  });

  test("only throttled is a session-level backoff", () {
    expect(UploadErrorCategory.throttled.isSessionLevel, isTrue);
    expect(UploadErrorCategory.network.isSessionLevel, isFalse);
  });
}
