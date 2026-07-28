import "package:drift/drift.dart" hide isNull, isNotNull;
import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/diagnostics/upload_diagnostics.dart";

void main() {
  late AppDatabase db;
  late UploadSessionDb dao;
  late UploadDiagnostics diagnostics;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = UploadSessionDb(db);
    diagnostics = UploadDiagnostics(sessionDb: dao);
  });

  tearDown(() async => db.close());

  test("aggregates state histogram and per-session progress", () async {
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: "s1",
        filepath: "documents://s1.mp4",
        fileSize: 200,
        fileName: "s1.mp4",
        mimeType: "video/mp4",
        state: const Value(SessionState.transferring),
        s3UploadId: const Value("upload-1"),
      ),
    );
    await dao.insertParts([
      UploadPartsCompanion.insert(
        sessionId: "s1",
        partNumber: 1,
        offset: 0,
        length: 100,
        state: const Value(PartState.uploaded),
      ),
      UploadPartsCompanion.insert(
        sessionId: "s1",
        partNumber: 2,
        offset: 100,
        length: 100,
      ),
    ]);
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: "s2",
        filepath: "documents://s2.mp4",
        fileSize: 100,
        fileName: "s2.mp4",
        mimeType: "video/mp4",
        state: const Value(SessionState.failedTerminal),
      ),
    );

    final snap = await diagnostics.snapshot();

    expect(snap["sessionCount"], 2);
    expect(snap["byState"], {"transferring": 1, "failedTerminal": 1});

    final sessions = (snap["sessions"] as List).cast<Map<String, Object?>>();
    final s1 = sessions.firstWhere((e) => e["id"] == "s1");
    expect(s1["progress"], 0.5); // 100 / 200 uploaded
    expect(s1["partsUploaded"], 1);
    expect(s1["partsTotal"], 2);
    expect(s1["hasMultipartUpload"], true);
  });

  test("never leaks presigned URLs (credentials)", () async {
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: "s1",
        filepath: "documents://s1.mp4",
        fileSize: 100,
        fileName: "s1.mp4",
        mimeType: "video/mp4",
      ),
    );
    await dao.insertParts([
      UploadPartsCompanion.insert(
        sessionId: "s1",
        partNumber: 1,
        offset: 0,
        length: 100,
        url: const Value("https://r2.example.com/secret-presigned-url?sig=abc"),
      ),
    ]);

    final snap = await diagnostics.snapshot();
    expect(snap.toString(), isNot(contains("presigned")));
    expect(snap.toString(), isNot(contains("r2.example.com")));
    expect(snap.toString(), isNot(contains("sig=")));
  });

  test("empty DB yields an empty, well-formed snapshot", () async {
    final snap = await diagnostics.snapshot();
    expect(snap["sessionCount"], 0);
    expect(snap["byState"], <String, int>{});
    expect(snap["sessions"], isEmpty);
  });
}
