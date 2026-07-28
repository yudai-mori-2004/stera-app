import "package:drift/drift.dart" hide isNull, isNotNull;
import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/schema/models/upload_part.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";
import "package:stera/src/services/upload_service/data/models/s3_presign_response.dart";

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    UploadDb.debugDatabase = db;
  });

  tearDown(() async {
    UploadDb.debugDatabase = null;
    await db.close();
  });

  test(
    "resetToNotStarted clears upload attempt metadata and keeps file info",
    () async {
      final id = await db
          .into(db.uploads)
          .insert(
            UploadsCompanion.insert(
              filepath: "documents://session_abc/clip.mp4",
              filesize: const Value(1024),
              fileName: const Value("clip.mp4"),
              mimeType: const Value("video/mp4"),
              thumnbnail: const Value("documents://session_abc/thumb.jpg"),
              status: const Value(UploadStatus.uploading),
              progress: const Value(0.42),
              retryCount: const Value(2),
              s3PresignResponse: Value(
                S3PresignResponse(
                  uploadUrl: "https://signed",
                  key: "profile/asset/clip.mp4",
                  folder: "profile/asset",
                  message: "ok",
                ),
              ),
              multipartStartResponse: Value(
                MultipartStartResponse(
                  uploadId: "u1",
                  key: "profile/asset/clip.mp4",
                  videoId: "asset-1",
                ),
              ),
              partUrls: Value([
                PartUrl(
                  partNumber: 1,
                  url: "https://signed/1",
                  expiresAt: DateTime.utc(2026, 6, 18),
                ),
              ]),
              uploadedParts: Value([
                UploadedPart(partNumber: 1, etag: "e1"),
              ]),
              partsCount: const Value(3),
            ),
          );

      final reset = await UploadDb.instance.resetToNotStarted(id);
      expect(reset, isNotNull);
      expect(reset!.status, UploadStatus.notStarted);
      expect(reset.filepath, "documents://session_abc/clip.mp4");
      expect(reset.fileName, "clip.mp4");
      expect(reset.thumnbnail, "documents://session_abc/thumb.jpg");
      expect(reset.progress, isNull);
      expect(reset.retryCount, 0);
      expect(reset.s3PresignResponse, isNull);
      expect(reset.multipartStartResponse, isNull);
      expect(reset.partUrls, isNull);
      expect(reset.uploadedParts, isNull);
      expect(reset.partsCount, isNull);
    },
  );

  test("resetToNotStarted returns null when the row does not exist", () async {
    expect(await UploadDb.instance.resetToNotStarted(999), isNull);
  });
}
