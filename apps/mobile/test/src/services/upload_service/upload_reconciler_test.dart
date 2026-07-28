import "package:drift/drift.dart" hide isNull, isNotNull;
import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/data/models/list_parts_response.dart";
import "package:stera/src/services/upload_service/reconcile/upload_reconciler.dart";

/// Hand-written fake (practice 09: no mocking framework) returning a canned
/// ListParts result for any (key, uploadId).
ListPartsFetcher fakeFetcher(
  (ListPartsResponse?, Failure?) result,
) => ({required String key, required String uploadId}) async => result;

void main() {
  late AppDatabase db;
  late UploadSessionDb dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = UploadSessionDb(db);
  });

  tearDown(() async => db.close());

  Future<void> seed({
    String id = "s1",
    SessionState state = SessionState.transferring,
    String? s3Key = "profile/asset/clip.mp4",
    String? s3UploadId = "u1",
  }) async {
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: id,
        filepath: "documents://$id.mp4",
        fileSize: 300,
        fileName: "$id.mp4",
        mimeType: "video/mp4",
        state: Value(state),
        s3Key: Value(s3Key),
        s3UploadId: Value(s3UploadId),
      ),
    );
    await dao.insertParts([
      for (var n = 1; n <= 3; n++)
        UploadPartsCompanion.insert(
          sessionId: id,
          partNumber: n,
          offset: (n - 1) * 100,
          length: 100,
        ),
    ]);
  }

  UploadReconciler reconcilerWith((ListPartsResponse?, Failure?) result) =>
      UploadReconciler(sessionDb: dao, fetchParts: fakeFetcher(result));

  Future<UploadPart> part(int n) => (db.select(
    db.uploadParts,
  )..where((p) => p.sessionId.equals("s1") & p.partNumber.equals(n))).getSingle();

  test("adopts a server part the local row hadn't marked uploaded", () async {
    await seed();
    final r = await reconcilerWith((
      ListPartsResponse(
        parts: [RemotePart(partNumber: 1, etag: "server-e1", size: 100)],
      ),
      null,
    )).reconcile("s1");

    expect(r.outcome, ReconcileOutcome.reconciled);
    expect(r.adopted, 1);
    final p1 = await part(1);
    expect(p1.state, PartState.uploaded);
    expect(p1.etag, "server-e1");
  });

  test("demotes a locally-uploaded part storage doesn't actually have", () async {
    await seed();
    await dao.markPartUploaded("s1", 2, etag: "local-e2");

    final r = await reconcilerWith((
      ListPartsResponse(parts: const []), // server has nothing
      null,
    )).reconcile("s1");

    expect(r.demoted, 1);
    expect((await part(2)).state, PartState.planned);
    expect((await part(2)).etag, isNull);
  });

  test("demotes on an ETag mismatch (re-upload, last write wins)", () async {
    await seed();
    await dao.markPartUploaded("s1", 1, etag: "local-e1");

    final r = await reconcilerWith((
      ListPartsResponse(
        parts: [RemotePart(partNumber: 1, etag: "DIFFERENT", size: 100)],
      ),
      null,
    )).reconcile("s1");

    expect(r.demoted, 1);
    expect((await part(1)).state, PartState.planned);
  });

  test("matching ETag is left untouched", () async {
    await seed();
    await dao.markPartUploaded("s1", 1, etag: "same");
    final r = await reconcilerWith((
      ListPartsResponse(
        parts: [RemotePart(partNumber: 1, etag: "same", size: 100)],
      ),
      null,
    )).reconcile("s1");
    expect(r.adopted, 0);
    expect(r.demoted, 0);
    expect((await part(1)).state, PartState.uploaded);
  });

  test("NoSuchUpload + object present → completedByServer", () async {
    await seed();
    final r = await reconcilerWith((
      ListPartsResponse(parts: const [], uploadExists: false, objectExists: true),
      null,
    )).reconcile("s1");

    expect(r.outcome, ReconcileOutcome.completedByServer);
    expect((await dao.getSession("s1"))!.state, SessionState.registeringAsset);
  });

  test("NoSuchUpload + no object → restartRequired", () async {
    await seed();
    final r = await reconcilerWith((
      ListPartsResponse(parts: const [], uploadExists: false, objectExists: false),
      null,
    )).reconcile("s1");

    expect(r.outcome, ReconcileOutcome.restartRequired);
    expect((await dao.getSession("s1"))!.state, SessionState.registering);
  });

  test("skips a session with no server identity yet", () async {
    await seed(s3Key: null, s3UploadId: null);
    final r = await reconcilerWith((ListPartsResponse(parts: const []), null))
        .reconcile("s1");
    expect(r.outcome, ReconcileOutcome.skipped);
  });

  test("reports failure when ListParts errors", () async {
    await seed();
    final r = await reconcilerWith((null, Failure.networkError())).reconcile("s1");
    expect(r.outcome, ReconcileOutcome.failed);
  });
}
