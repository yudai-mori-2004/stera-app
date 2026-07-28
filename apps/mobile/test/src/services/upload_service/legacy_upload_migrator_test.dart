import "package:drift/drift.dart";
import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/schema/models/upload_part.dart";
import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";
import "package:stera/src/services/legacy_upload_migration_service/legacy_upload_migration_service.dart";

void main() {
  late AppDatabase db;
  late LegacyUploadMigrator migrator;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    migrator = LegacyUploadMigrator(db: db, chunkSize: 100); // tiny chunk for clear math
  });

  tearDown(() async => db.close());

  Future<void> insertLegacy({
    required UploadStatus status,
    int? filesize,
    int? partsCount,
    List<UploadedPart>? uploaded,
    MultipartStartResponse? start,
  }) async {
    await db
        .into(db.uploads)
        .insert(
          UploadsCompanion.insert(
            filepath: "documents://clip.mp4",
            filesize: Value(filesize),
            fileName: const Value("clip.mp4"),
            mimeType: const Value("video/mp4"),
            status: Value(status),
            partsCount: Value(partsCount),
            uploadedParts: Value(uploaded),
            multipartStartResponse: Value(start),
          ),
        );
  }

  test("migrates a failed row into a session + uploaded/planned parts", () async {
    await insertLegacy(
      status: UploadStatus.failed,
      filesize: 250, // 3 parts at chunk 100 → 100,100,50
      uploaded: [UploadedPart(etag: "e1", partNumber: 1)],
      start: MultipartStartResponse(uploadId: "u1", key: "k1", videoId: "asset1"),
    );

    expect(await migrator.migrateIdleRows(), 1);

    final session = await db.select(db.uploadSessions).getSingle();
    expect(session.state, SessionState.failedTerminal);
    expect(session.s3UploadId, "u1");
    expect(session.s3Key, "k1");
    expect(session.assetId, "asset1");
    expect(session.partCount, 3);

    final parts =
        await (db.select(db.uploadParts)
              ..orderBy([(p) => OrderingTerm.asc(p.partNumber)]))
            .get();
    expect(parts.length, 3);
    expect(parts[0].state, PartState.uploaded);
    expect(parts[0].etag, "e1");
    expect(parts[1].state, PartState.planned);
    expect(parts[2].length, 50); // remainder part
  });

  test("is idempotent — re-running migrates nothing new", () async {
    await insertLegacy(status: UploadStatus.failed, filesize: 100);
    expect(await migrator.migrateIdleRows(), 1);
    expect(await migrator.migrateIdleRows(), 0);
  });

  test("leaves actively-uploading rows on the legacy path", () async {
    await insertLegacy(status: UploadStatus.uploading, filesize: 100);
    expect(await migrator.migrateIdleRows(), 0);
    expect(await db.select(db.uploadSessions).get(), isEmpty);
  });

  test("skips rows without a known file size", () async {
    await insertLegacy(status: UploadStatus.pending, filesize: null);
    expect(await migrator.migrateIdleRows(), 0);
  });
}
