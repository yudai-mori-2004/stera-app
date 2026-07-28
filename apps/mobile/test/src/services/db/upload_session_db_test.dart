import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:drift/drift.dart";

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedSession(String id) => db.into(db.uploadSessions).insert(
    UploadSessionsCompanion.insert(
      id: id,
      filepath: "documents://$id.mp4",
      fileSize: 300,
      fileName: "$id.mp4",
      mimeType: "video/mp4",
    ),
  );

  test("inserts a session defaulting to queued", () async {
    await seedSession("s1");
    final row = await (db.select(
      db.uploadSessions,
    )..where((s) => s.id.equals("s1"))).getSingle();
    expect(row.state, SessionState.queued);
  });

  test("part rows: pending excludes uploaded; progress is derived", () async {
    await seedSession("s1");
    await db.batch((b) {
      b.insertAll(db.uploadParts, [
        UploadPartsCompanion.insert(
          sessionId: "s1",
          partNumber: 1,
          offset: 0,
          length: 100,
        ),
        UploadPartsCompanion.insert(
          sessionId: "s1",
          partNumber: 2,
          offset: 100,
          length: 100,
        ),
        UploadPartsCompanion.insert(
          sessionId: "s1",
          partNumber: 3,
          offset: 200,
          length: 100,
        ),
      ]);
    });

    // Mark part 1 uploaded.
    await (db.update(db.uploadParts)..where(
      (p) => p.sessionId.equals("s1") & p.partNumber.equals(1),
    )).write(
      const UploadPartsCompanion(
        state: Value(PartState.uploaded),
        etag: Value("etag-1"),
      ),
    );

    final pending = await (db.select(
      db.uploadParts,
    )..where((p) => p.state.equals(PartState.uploaded.name).not())).get();
    expect(pending.map((p) => p.partNumber), [2, 3]);

    final uploadedBytes = (await db.select(db.uploadParts).get())
        .where((p) => p.state == PartState.uploaded)
        .fold<int>(0, (sum, p) => sum + p.length);
    expect(uploadedBytes, 100);
  });
}
