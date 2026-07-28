import "dart:async";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/schema/enums/upload_error_category.dart";
import "package:stera/src/services/upload_service/retry/upload_error_classifier.dart";

void main() {
  group("UploadErrorClassifier.fromNativeCode", () {
    test("maps the documented native channel codes", () {
      expect(
        UploadErrorClassifier.fromNativeCode("timeout"),
        UploadErrorCategory.timeout,
      );
      expect(
        UploadErrorClassifier.fromNativeCode("urlExpired"),
        UploadErrorCategory.urlExpired,
      );
      expect(
        UploadErrorClassifier.fromNativeCode("http_5xx"),
        UploadErrorCategory.serverError,
      );
      expect(
        UploadErrorClassifier.fromNativeCode("diskFull"),
        UploadErrorCategory.diskFull,
      );
    });

    test("maps legacy Impl strings and is case-insensitive", () {
      expect(
        UploadErrorClassifier.fromNativeCode("FILE_READ_FAILED"),
        UploadErrorCategory.fileError,
      );
      expect(
        UploadErrorClassifier.fromNativeCode("TEMP_FILE_WRITE_FAILED"),
        UploadErrorCategory.diskFull,
      );
    });

    test("returns null for an unknown code", () {
      expect(UploadErrorClassifier.fromNativeCode("banana"), isNull);
    });
  });

  group("UploadErrorClassifier.fromHttpStatus", () {
    test("403 is treated as an expired presigned URL", () {
      expect(
        UploadErrorClassifier.fromHttpStatus(403),
        UploadErrorCategory.urlExpired,
      );
    });

    test("401 → auth, 429 → throttled, 5xx → server, other 4xx → client", () {
      expect(
        UploadErrorClassifier.fromHttpStatus(401),
        UploadErrorCategory.authError,
      );
      expect(
        UploadErrorClassifier.fromHttpStatus(429),
        UploadErrorCategory.throttled,
      );
      expect(
        UploadErrorClassifier.fromHttpStatus(503),
        UploadErrorCategory.serverError,
      );
      expect(
        UploadErrorClassifier.fromHttpStatus(400),
        UploadErrorCategory.clientError,
      );
    });

    test("2xx is not an error", () {
      expect(UploadErrorClassifier.fromHttpStatus(200), isNull);
    });
  });

  group("UploadErrorClassifier.classify", () {
    test("prefers native code over http status over exception", () {
      expect(
        UploadErrorClassifier.classify(
          nativeErrorCode: "timeout",
          httpStatus: 500,
        ),
        UploadErrorCategory.timeout,
      );
    });

    test("classifies Dart exceptions", () {
      expect(
        UploadErrorClassifier.classify(error: TimeoutException("x")),
        UploadErrorCategory.timeout,
      );
      expect(
        UploadErrorClassifier.classify(
          error: const SocketException("no route"),
        ),
        UploadErrorCategory.network,
      );
    });

    test("a no-space file system error is diskFull, others are fileError", () {
      expect(
        UploadErrorClassifier.classify(
          error: const FileSystemException(
            "write failed",
            "/tmp/x",
            OSError("No space left on device", 28),
          ),
        ),
        UploadErrorCategory.diskFull,
      );
      expect(
        UploadErrorClassifier.classify(
          error: const FileSystemException("missing", "/tmp/gone"),
        ),
        UploadErrorCategory.fileError,
      );
    });

    test("falls back to retryable network for an unrecognised blip", () {
      expect(UploadErrorClassifier.classify(), UploadErrorCategory.network);
    });
  });
}
