import "dart:math";

import "package:drift/drift.dart" hide isNull, isNotNull;
import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/schema/enums/upload_error_category.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_chunk_planner.dart";
import "package:stera/src/services/upload_service/orchestrator/upload_orchestrator.dart";
import "package:stera/src/services/upload_service/retry/upload_retry_policy.dart";

class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => (value * max).floor();
  @override
  bool nextBool() => value >= 0.5;
}

void main() {
  late AppDatabase db;
  late UploadSessionDb dao;
  late UploadOrchestrator orch;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = UploadSessionDb(db);
    orch = UploadOrchestrator(
      sessionDb: dao,
      retryPolicy: UploadRetryPolicy(random: _FixedRandom(0.5)),
      now: () => DateTime.utc(2026, 6, 14, 12),
    );
  });

  tearDown(() async => db.close());

  Future<void> seed(
    String id, {
    int fileSize = 300,
    int chunkSize = 100,
    SessionState state = SessionState.transferring,
  }) async {
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: id,
        filepath: "documents://$id.mp4",
        fileSize: fileSize,
        fileName: "$id.mp4",
        mimeType: "video/mp4",
        state: Value(state),
      ),
    );
    final plan = UploadChunkPlanner.plan(fileSize: fileSize, chunkSize: chunkSize);
    await dao.insertParts([
      for (final e in plan)
        UploadPartsCompanion.insert(
          sessionId: id,
          partNumber: e.partNumber,
          offset: e.offset,
          length: e.length,
        ),
    ]);
  }

  test("part completion advances progress; last part → finalizing", () async {
    await seed("s1"); // 3 parts of 100
    expect(
      await orch.recordPartCompleted("s1", 1, etag: "e1"),
      SessionState.transferring,
    );
    expect(await orch.progressFor("s1"), closeTo(100 / 300, 1e-9));

    await orch.recordPartCompleted("s1", 2, etag: "e2");
    final state = await orch.recordPartCompleted("s1", 3, etag: "e3");
    expect(state, SessionState.finalizing);
    expect(await orch.progressFor("s1"), 1.0);
  });

  test("urlExpired demotes the part and re-presigns without spending budget", () async {
    await seed("s1");
    final action = await orch.recordPartFailed(
      "s1",
      1,
      UploadErrorCategory.urlExpired,
    );
    expect(action.kind, PartRetryKind.refreshUrl);

    final part = await (db.select(db.uploadParts)..where(
      (p) => p.sessionId.equals("s1") & p.partNumber.equals(1),
    )).getSingle();
    expect(part.state, PartState.planned);
    expect(part.url, isNull);
    expect(part.attempts, 0); // urlExpired must not consume the budget
  });

  test("a network part failure retries and increments attempts", () async {
    await seed("s1");
    final action = await orch.recordPartFailed(
      "s1",
      1,
      UploadErrorCategory.network,
    );
    expect(action.kind, PartRetryKind.retry);
    final part = await (db.select(db.uploadParts)..where(
      (p) => p.sessionId.equals("s1") & p.partNumber.equals(1),
    )).getSingle();
    expect(part.attempts, 1);
    expect(part.lastErrorCode, "network");
  });

  test("a non-retryable part error fails the whole session", () async {
    await seed("s1");
    final action = await orch.recordPartFailed(
      "s1",
      1,
      UploadErrorCategory.clientError,
    );
    expect(action.kind, PartRetryKind.giveUp);
    expect((await dao.getSession("s1"))!.state, SessionState.failedTerminal);
  });

  test("per-URL attempts reset on refresh while total keeps climbing", () async {
    await seed("s1");
    Future<UploadPart> part1() => (db.select(db.uploadParts)
          ..where((p) => p.sessionId.equals("s1") & p.partNumber.equals(1)))
        .getSingle();

    // 5 network failures on the same URL → 5th refreshes the URL.
    PartRetryAction? action;
    for (var i = 0; i < 5; i++) {
      action = await orch.recordPartFailed("s1", 1, UploadErrorCategory.network);
    }
    expect(action!.kind, PartRetryKind.refreshUrl);
    final afterRefresh = await part1();
    expect(afterRefresh.attempts, 5); // total kept climbing
    expect(afterRefresh.attemptsAtUrl, 0); // per-URL reset by the refresh
    expect(afterRefresh.state, PartState.planned);

    // urlExpired never consumes either budget.
    await orch.recordPartFailed("s1", 1, UploadErrorCategory.urlExpired);
    final afterExpiry = await part1();
    expect(afterExpiry.attempts, 5);
    expect(afterExpiry.attemptsAtUrl, 0);
  });

  test("session failure schedules backoff, then fails at budget", () async {
    await seed("s1");
    final first = await orch.recordSessionFailure(
      "s1",
      UploadErrorCategory.network,
    );
    expect(first.kind, SessionRetryKind.retry);
    var s = (await dao.getSession("s1"))!;
    expect(s.state, SessionState.waitingRetry);
    expect(s.attemptsWithoutProgress, 1);
    expect(s.nextAttemptAt, isNotNull);

    for (var i = 0; i < 6; i++) {
      await orch.recordSessionFailure("s1", UploadErrorCategory.network);
    }
    s = (await dao.getSession("s1"))!;
    expect(s.state, SessionState.failedTerminal);
  });

  test("completing a part resets the session no-progress counter", () async {
    await seed("s1");
    await orch.recordSessionFailure("s1", UploadErrorCategory.network);
    expect((await dao.getSession("s1"))!.attemptsWithoutProgress, 1);

    await orch.recordPartCompleted("s1", 1, etag: "e1");
    expect((await dao.getSession("s1"))!.attemptsWithoutProgress, 0);
  });

  test("manual retry requeues, preserving uploaded parts", () async {
    await seed("s1", state: SessionState.failedTerminal);
    await dao.markPartUploaded("s1", 1, etag: "e1");

    await orch.retrySession("s1");

    final s = (await dao.getSession("s1"))!;
    expect(s.state, SessionState.queued);
    expect(s.attemptsWithoutProgress, 0);
    expect(s.lastErrorCode, isNull);
    expect((await dao.partCounts("s1")).uploaded, 1); // preserved (W7)
  });

  test("dueForRetry returns sessions whose backoff has elapsed", () async {
    await seed("s1");
    await orch.recordSessionFailure("s1", UploadErrorCategory.network);
    // nextAttemptAt is now+30s; at the fixed clock it is in the future.
    expect(await orch.dueForRetry(), isEmpty);

    // Force the backoff into the past.
    await (db.update(db.uploadSessions)..where((x) => x.id.equals("s1"))).write(
      UploadSessionsCompanion(
        nextAttemptAt: Value(DateTime.utc(2026, 6, 14, 11)),
      ),
    );
    expect((await orch.dueForRetry()).map((e) => e.id), ["s1"]);
  });
}
