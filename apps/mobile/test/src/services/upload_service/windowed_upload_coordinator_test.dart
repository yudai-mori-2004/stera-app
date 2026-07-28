import "dart:io";

import "package:drift/drift.dart" hide isNull, isNotNull;
import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/channels/ios_windowed_uploader_service.dart";
import "package:stera/src/services/upload_service/data/models/list_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_finalize_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";
import "package:stera/src/services/upload_service/coordinator/windowed_upload_coordinator.dart";
import "package:stera/src/services/upload_service/orchestrator/upload_orchestrator.dart";
import "package:stera/src/services/upload_service/presign/presign_manager.dart";
import "package:stera/src/services/upload_service/reconcile/upload_reconciler.dart";

class _FakeEngine implements WindowedUploadEngine {
  final List<List<WindowedPartPlan>> provided = [];
  final List<WindowedSessionManifest> began = [];
  final List<List<Map<String, dynamic>>> acknowledged = [];
  final List<int> concurrencyPushes = [];
  List<Map<String, dynamic>>? drainRows;
  @override
  Stream<WindowedUploadEvent> events() => const Stream.empty();
  @override
  Future<Failure?> beginSession(WindowedSessionManifest m) async {
    began.add(m);
    return null;
  }

  @override
  Future<Failure?> provideUrls(String s, List<WindowedPartPlan> parts) async {
    provided.add(parts);
    return null;
  }

  @override
  Future<Failure?> pauseSession(String s) async => null;
  @override
  Future<Failure?> cancelSession(String s) async => null;
  @override
  Future<Failure?> setAppForegrounded({required bool foregrounded}) async =>
      null;
  @override
  Future<Failure?> setTransferConcurrency({required int maxInFlight}) async {
    concurrencyPushes.add(maxInFlight);
    return null;
  }
  @override
  Future<(List<Map<String, dynamic>>, Failure?)> drainJournal({
    String? sessionId,
  }) async => (drainRows ?? <Map<String, dynamic>>[], null);
  @override
  Future<int> freeDiskBytes() async => 1 << 60;
  Future<Map<String, dynamic>> nativeDiagnostics() async => const {};
  @override
  Future<Failure?> acknowledgeDrain(List<Map<String, dynamic>> rows) async {
    acknowledged.add(rows);
    return null;
  }
}

void main() {
  late AppDatabase db;
  late UploadSessionDb dao;
  late _FakeEngine engine;
  final now = DateTime.utc(2026, 6, 14, 12);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = UploadSessionDb(db);
    engine = _FakeEngine();
  });

  tearDown(() async => db.close());

  Future<void> seed({int parts = 3}) async {
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: "s1",
        filepath: "documents://s1.mp4",
        fileSize: parts * 100,
        fileName: "s1.mp4",
        mimeType: "video/mp4",
        state: const Value(SessionState.transferring),
        s3Key: const Value("profile/asset/clip.mp4"),
        s3UploadId: const Value("u1"),
        chunkSize: const Value(100),
        partCount: Value(parts),
      ),
    );
    await dao.insertParts([
      for (var n = 1; n <= parts; n++)
        UploadPartsCompanion.insert(
          sessionId: "s1",
          partNumber: n,
          offset: (n - 1) * 100,
          length: 100,
        ),
    ]);
  }

  PartUrlFetcher presignFake() =>
      ({required key, required uploadId, partCount, partNumbers}) async => (
        MultipartPartsResponse(
          urls: [
            for (final n in partNumbers ?? const <int>[])
              PartUrl(
                partNumber: n,
                url: "https://signed/$n",
                expiresAt: now.add(const Duration(days: 1)),
              ),
          ],
        ),
        null,
      );

  ListPartsFetcher reconcileFake(List<RemotePart> parts) =>
      ({required key, required uploadId}) async =>
          (ListPartsResponse(parts: parts), null);

  WindowedUploadCoordinator build({
    ListPartsFetcher? reconcile,
    FinalizeUploadFn? finalizeUpload,
    FreeDiskBytesFn? freeDiskBytes,
    PartUrlFetcher? presign,
    ResolveFilePathFn? resolveFilePath,
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? wait,
    int presignBatchSize = 256,
    bool replayStart = false,
  }) => WindowedUploadCoordinator(
    sessionDb: dao,
    orchestrator: UploadOrchestrator(sessionDb: dao),
    presignManager: PresignManager(
      sessionDb: dao,
      fetchUrls: presign ?? presignFake(),
      batchSize: presignBatchSize,
      now: () => now,
    ),
    reconciler: UploadReconciler(
      sessionDb: dao,
      fetchParts: reconcile ?? reconcileFake(const []),
    ),
    engine: engine,
    finalizeUpload:
        finalizeUpload ??
        ({required key, required uploadId, required partCount}) async => (
          MultipartFinalizeResponse(completed: true, uploadedParts: partCount),
          null,
        ),
    registerAsset: (s) async => null,
    startMultipart:
        ({required fileName, required contentType, clientUploadId}) async => (
          MultipartStartResponse(
            uploadId: "u1",
            key: "profile/asset/clip.mp4",
            videoId: "asset-1",
            idempotentReplay: replayStart,
          ),
          null,
        ),
    resolveFilePath: resolveFilePath ?? (stored) async => "/tmp/$stored",
    freeDiskBytes: freeDiskBytes,
    now: clock,
    wait: wait,
  );

  test(
    "needUrls fetches a batch and pushes fresh URLs to the engine",
    () async {
      await seed();
      await build().applyEvent(
        const WindowedNeedUrls("s1", partNumbers: [1, 2, 3]),
      );

      expect(engine.provided, isNotEmpty);
      expect(engine.provided.first.map((p) => p.partNumber).toSet(), {1, 2, 3});
      // Parts now hold URLs in the DB.
      final p1 =
          await (db.select(db.uploadParts)..where(
                (p) => p.sessionId.equals("s1") & p.partNumber.equals(1),
              ))
              .getSingle();
      expect(p1.state, PartState.urlReady);
      expect(p1.url, "https://signed/1");
    },
  );

  test(
    "a non-final part completion advances state without finalizing",
    () async {
      await seed();
      await build().applyEvent(
        const WindowedPartCompleted("s1", partNumber: 1, etag: "e1"),
      );

      final session = await dao.getSession("s1");
      expect(
        session!.state,
        SessionState.transferring,
      ); // 2 parts still pending
      expect((await dao.partCounts("s1")).uploaded, 1);
    },
  );

  test(
    "partFailed with urlExpired triggers a URL refresh to the engine",
    () async {
      await seed();
      await build().applyEvent(
        const WindowedPartFailed("s1", partNumber: 1, errorCode: "urlExpired"),
      );
      expect(engine.provided, isNotEmpty);
    },
  );

  test(
    "partFailed with a retryable error re-pushes the part to native after backoff",
    () async {
      await seed();
      // The failing part holds a fresh URL — exactly the state a part is in
      // when its PUT comes back 5xx (native parks it as `error`; Drift keeps
      // it urlReady for a same-URL retry).
      await dao.updatePart(
        "s1",
        1,
        UploadPartsCompanion(
          state: const Value(PartState.urlReady),
          url: const Value("https://signed/1"),
          urlExpiresAt: Value(now.add(const Duration(days: 1))),
        ),
      );
      final waits = <Duration>[];
      final coordinator = build(wait: (d) async => waits.add(d));

      await coordinator.applyEvent(
        const WindowedPartFailed("s1", partNumber: 1, errorCode: "http_5xx"),
      );
      await pumpEventQueue();

      // The policy chose retry-with-backoff, and the part was re-pushed so
      // the native journal upsert returns it to `planned` — without this the
      // parked part is never rescheduled and the session wedges.
      expect(waits, hasLength(1));
      expect(waits.single, greaterThan(Duration.zero));
      expect(engine.provided, hasLength(1));
      expect(engine.provided.single.map((p) => p.partNumber), [1]);
      expect(engine.provided.single.single.url, "https://signed/1");
    },
  );

  test(
    "the backoff re-push is skipped when the session fails during the wait",
    () async {
      await seed();
      await dao.updatePart(
        "s1",
        1,
        UploadPartsCompanion(
          state: const Value(PartState.urlReady),
          url: const Value("https://signed/1"),
          urlExpiresAt: Value(now.add(const Duration(days: 1))),
        ),
      );
      // While the backoff is pending the session reaches a terminal state
      // (e.g. another part exhausted its budget) — the requeue must not push
      // parts for a dead session.
      final coordinator = build(
        wait: (_) => dao.markSessionFailed("s1", errorCode: "serverError"),
      );

      await coordinator.applyEvent(
        const WindowedPartFailed("s1", partNumber: 1, errorCode: "http_5xx"),
      );
      await pumpEventQueue();

      expect(engine.provided, isEmpty);
    },
  );

  test(
    "sessionDrained reconciles, finalizes server-side, and completes",
    () async {
      await seed();
      // All parts uploaded locally with etags that match storage.
      for (var n = 1; n <= 3; n++) {
        await dao.markPartUploaded("s1", n, etag: "e$n");
      }
      final coordinator = build(
        reconcile: reconcileFake([
          RemotePart(partNumber: 1, etag: "e1", size: 100),
          RemotePart(partNumber: 2, etag: "e2", size: 100),
          RemotePart(partNumber: 3, etag: "e3", size: 100),
        ]),
      );

      await coordinator.applyEvent(const WindowedSessionDrained("s1"));

      expect((await dao.getSession("s1"))!.state, SessionState.completed);
    },
  );

  test(
    "startSession freezes the plan, registers, presigns, and begins native",
    () async {
      await dao.insertSession(
        UploadSessionsCompanion.insert(
          id: "s1",
          filepath: "documents://s1.mp4",
          fileSize: 250,
          fileName: "s1.mp4",
          mimeType: "video/mp4",
          state: const Value(SessionState.queued),
        ),
      );

      final err = await build().startSession("s1");
      expect(err, isNull);

      final session = (await dao.getSession("s1"))!;
      expect(session.state, SessionState.transferring);
      expect(session.chunkSize, isNotNull);
      expect(session.partCount, isNotNull);
      expect(session.s3UploadId, "u1");
      expect(session.assetId, "asset-1");

      expect(engine.began, hasLength(1));
      expect(engine.began.first.fileUrl, "/tmp/documents://s1.mp4");
      expect(engine.began.first.parts, isNotEmpty);
    },
  );

  test(
    "startSession refuses to begin when disk headroom is insufficient",
    () async {
      await dao.insertSession(
        UploadSessionsCompanion.insert(
          id: "s1",
          filepath: "documents://s1.mp4",
          fileSize: 250,
          fileName: "s1.mp4",
          mimeType: "video/mp4",
          state: const Value(SessionState.queued),
        ),
      );

      // Pretend only 1 KB is free — far below windowSize × chunkSize.
      final err = await build(
        freeDiskBytes: () async => 1024,
      ).startSession("s1");

      expect(err, isNotNull);
      expect(err!.code, ErrorType.insufficientStorage);
      // Nothing was registered or handed to native; the session stays retryable.
      expect(engine.began, isEmpty);
      final session = (await dao.getSession("s1"))!;
      expect(session.state, SessionState.queued);
      expect(session.s3UploadId, isNull);
    },
  );

  test(
    "startSession on resume adopts a server-landed part instead of re-uploading it",
    () async {
      await seed(); // transferring, s3UploadId="u1", 3 planned parts
      // Part 2's PUT actually landed on R2 before a force-quit cancelled its task.
      final coordinator = build(
        reconcile: reconcileFake([
          RemotePart(partNumber: 2, etag: "e2", size: 100),
        ]),
      );

      final err = await coordinator.startSession("s1");
      expect(err, isNull);

      // Part 2 is adopted (uploaded) — never re-uploaded.
      final p2 =
          await (db.select(db.uploadParts)..where(
                (p) => p.sessionId.equals("s1") & p.partNumber.equals(2),
              ))
              .getSingle();
      expect(p2.state, PartState.uploaded);
      expect(p2.etag, "e2");

      // Only the genuinely-missing parts (1, 3) are handed to native.
      expect(engine.began, hasLength(1));
      expect(engine.began.first.parts.map((p) => p.partNumber).toSet(), {1, 3});
    },
  );

  test(
    "startSession on resume finalizes when reconcile shows every part already on storage",
    () async {
      await seed();
      // All three parts already landed server-side (e.g. the window finished in
      // the background, then the app was force-quit before Dart recorded them).
      final coordinator = build(
        reconcile: reconcileFake([
          RemotePart(partNumber: 1, etag: "e1", size: 100),
          RemotePart(partNumber: 2, etag: "e2", size: 100),
          RemotePart(partNumber: 3, etag: "e3", size: 100),
        ]),
      );

      final err = await coordinator.startSession("s1");
      expect(err, isNull);

      // Nothing re-uploaded; the session is driven straight to completion.
      expect(engine.began, isEmpty);
      expect((await dao.getSession("s1"))!.state, SessionState.completed);
    },
  );

  test(
    "startSession adopts R2 parts when /start replays after a logout wipe",
    () async {
      // Post-logout: the local Uploads journal was wiped, so the recording is
      // re-added as a *fresh* session — no s3UploadId (isResume would be false),
      // parts only planned. But /start dedupes on the recording-stable
      // clientUploadId and replays the original upload, which already holds part
      // 2 in R2. The replay flag must trigger reconcile so we resume.
      await dao.insertSession(
        UploadSessionsCompanion.insert(
          id: "s1",
          filepath: "documents://s1.mp4",
          fileSize: 300,
          fileName: "s1.mp4",
          mimeType: "video/mp4",
          state: const Value(SessionState.queued),
          chunkSize: const Value(100),
          partCount: const Value(3),
        ),
      );
      await dao.insertParts([
        for (var n = 1; n <= 3; n++)
          UploadPartsCompanion.insert(
            sessionId: "s1",
            partNumber: n,
            offset: (n - 1) * 100,
            length: 100,
          ),
      ]);

      final coordinator = build(
        replayStart: true,
        reconcile: reconcileFake([
          RemotePart(partNumber: 2, etag: "e2", size: 100),
        ]),
      );

      final err = await coordinator.startSession("s1");
      expect(err, isNull);

      // Part 2 adopted from R2 — not re-uploaded.
      final p2 =
          await (db.select(db.uploadParts)..where(
                (p) => p.sessionId.equals("s1") & p.partNumber.equals(2),
              ))
              .getSingle();
      expect(p2.state, PartState.uploaded);
      expect(p2.etag, "e2");

      // Only the missing parts (1, 3) go to native.
      expect(engine.began, hasLength(1));
      expect(engine.began.first.parts.map((p) => p.partNumber).toSet(), {1, 3});
    },
  );

  test("startSession fully presigns before beginning native", () async {
    await seed(parts: 5); // resume session, 5 planned parts
    // Batch size 2 forces multiple backend presign round-trips. Native should
    // still receive the whole runway in BEGIN, before Dart can suspend.
    final coordinator = build(presignBatchSize: 2);

    final err = await coordinator.startSession("s1");
    expect(err, isNull);

    expect(engine.began, hasLength(1));
    expect(engine.began.first.parts.map((p) => p.partNumber).toSet(), {
      1,
      2,
      3,
      4,
      5,
    });
    expect(engine.provided, isEmpty);

    final parts = await dao.getParts("s1");
    expect(parts.where((p) => p.state == PartState.urlReady), hasLength(5));
  });

  test("resumeOnLaunch acknowledges drained journal rows", () async {
    engine.drainRows = [
      {"sessionId": "s1", "partNumber": 1, "state": "uploaded", "etag": "e1"},
    ];
    await seed();
    await build().resumeOnLaunch();
    expect(engine.acknowledged, hasLength(1));
    expect(engine.acknowledged.first, hasLength(1));
  });

  test("resumeOnLaunch finalizes registeringAsset sessions", () async {
    await seed();
    for (var n = 1; n <= 3; n++) {
      await dao.markPartUploaded("s1", n, etag: "e$n");
    }
    await dao.setSessionState("s1", SessionState.registeringAsset);
    await build(
      reconcile: reconcileFake([
        RemotePart(partNumber: 1, etag: "e1", size: 100),
        RemotePart(partNumber: 2, etag: "e2", size: 100),
        RemotePart(partNumber: 3, etag: "e3", size: 100),
      ]),
    ).resumeOnLaunch();
    expect((await dao.getSession("s1"))!.state, SessionState.completed);
  });

  test(
    "resumeOnLaunch promotes all-parts-uploaded transferring to finalize",
    () async {
      await seed();
      for (var n = 1; n <= 3; n++) {
        await dao.markPartUploaded("s1", n, etag: "e$n");
      }
      await build(
        reconcile: reconcileFake([
          RemotePart(partNumber: 1, etag: "e1", size: 100),
          RemotePart(partNumber: 2, etag: "e2", size: 100),
          RemotePart(partNumber: 3, etag: "e3", size: 100),
        ]),
      ).resumeOnLaunch();
      expect((await dao.getSession("s1"))!.state, SessionState.completed);
    },
  );

  test(
    "resetForRetry re-arms a failedTerminal session + stuck parts, keeping uploaded ones",
    () async {
      await seed(); // 3 parts, transferring, s3UploadId=u1
      // Part 1 uploaded; part 2 exhausted its retry budget; part 3 still planned.
      await dao.markPartUploaded("s1", 1, etag: "e1");
      await dao.updatePart(
        "s1",
        2,
        const UploadPartsCompanion(
          state: Value(PartState.urlReady),
          attempts: Value(15),
          attemptsAtUrl: Value(5),
          url: Value("https://stale/2"),
        ),
      );
      await dao.markSessionFailed(
        "s1",
        errorCode: "unknown",
        errorDetail: "part 2 exhausted its retry budget",
      );

      await dao.resetForRetry("s1");

      final session = (await dao.getSession("s1"))!;
      expect(session.state, SessionState.queued);
      expect(session.attemptsWithoutProgress, 0);
      expect(session.lastErrorCode, isNull);

      final parts = {
        for (final p in await dao.getParts("s1")) p.partNumber: p,
      };
      // Uploaded part preserved — resume continues from where it left off.
      expect(parts[1]!.state, PartState.uploaded);
      expect(parts[1]!.etag, "e1");
      // Stuck part gets a clean slate: fresh budget, dropped stale URL.
      expect(parts[2]!.state, PartState.planned);
      expect(parts[2]!.attempts, 0);
      expect(parts[2]!.attemptsAtUrl, 0);
      expect(parts[2]!.url, isNull);
    },
  );

  test(
    "a needUrls loop that can't presign anything fails the session (circuit breaker)",
    () async {
      await seed(); // transferring, s3UploadId=u1, 3 planned parts
      // Presign never returns a URL → every needUrls round assigns 0. This is
      // the wedged-desync signature from the field logs (native asks forever,
      // Dart presigns nothing); the breaker must stop the spin and fail it.
      final coordinator = build(
        presign: ({required key, required uploadId, partCount, partNumbers}) async =>
            (MultipartPartsResponse(urls: const []), null),
      );

      for (var i = 0; i < 12; i++) {
        await coordinator.applyEvent(
          const WindowedNeedUrls("s1", partNumbers: [1, 2, 3]),
        );
      }

      final session = (await dao.getSession("s1"))!;
      expect(session.state, SessionState.failedTerminal);
      expect(session.lastErrorCode, "needUrlsStall");
    },
  );

  test("finalize stays put when the server isn't ready yet", () async {
    await seed();
    final coordinator = build(
      finalizeUpload:
          ({required key, required uploadId, required partCount}) async => (
            MultipartFinalizeResponse(completed: false, uploadedParts: 1),
            null,
          ),
    );

    await coordinator.finalize("s1");
    // Not completed — stays in finalizing for a later retry.
    expect((await dao.getSession("s1"))!.state, SessionState.finalizing);
  });

  test("startSession fails terminally on a zero-size session", () async {
    // A zero fileSize yields an empty chunk plan (partCount 0) — native would
    // drain instantly and the server finalize complete vacuously with nothing
    // in R2 (the 1.5 h / 0 s-duration field incident).
    await dao.insertSession(
      UploadSessionsCompanion.insert(
        id: "s1",
        filepath: "documents://s1.mp4",
        fileSize: 0,
        fileName: "s1.mp4",
        mimeType: "video/mp4",
        state: const Value(SessionState.queued),
      ),
    );

    final err = await build().startSession("s1");

    expect(err, isNotNull);
    expect(err!.code, ErrorType.uploadInComplete);
    final session = (await dao.getSession("s1"))!;
    expect(session.state, SessionState.failedTerminal);
    expect(session.lastErrorCode, "zeroFileSize");
    // Nothing registered or handed to native.
    expect(session.s3UploadId, isNull);
    expect(engine.began, isEmpty);
  });

  test(
    "finalize refuses a zero-part plan instead of completing vacuously",
    () async {
      // Session already registered but with an empty frozen plan — the server
      // finalize would pass its "all partCount parts present" check for 0 and
      // register a 0 s asset with nothing in R2. The guard must fail the
      // session without ever calling the server.
      await dao.insertSession(
        UploadSessionsCompanion.insert(
          id: "s1",
          filepath: "documents://s1.mp4",
          fileSize: 0,
          fileName: "s1.mp4",
          mimeType: "video/mp4",
          state: const Value(SessionState.finalizing),
          s3Key: const Value("profile/asset/clip.mp4"),
          s3UploadId: const Value("u1"),
          chunkSize: const Value(100),
          partCount: const Value(0),
        ),
      );

      var finalizeCalls = 0;
      final coordinator = build(
        finalizeUpload:
            ({required key, required uploadId, required partCount}) async {
              finalizeCalls++;
              return (
                MultipartFinalizeResponse(completed: true, uploadedParts: 0),
                null,
              );
            },
      );

      await coordinator.finalize("s1");

      expect(finalizeCalls, 0);
      final session = (await dao.getSession("s1"))!;
      expect(session.state, SessionState.failedTerminal);
      expect(session.lastErrorCode, "zeroPartCount");
    },
  );

  test(
    "startSession fails terminally when on-disk bytes disagree with the frozen plan",
    () async {
      // The plan says 300 bytes but the file on disk holds 250 — a row
      // snapshotted while the recording was still being finalized. Uploading
      // would ship a torn object that "completes" but never verifies.
      final dir = await Directory.systemTemp.createTemp("wuc_size_mismatch");
      addTearDown(() => dir.delete(recursive: true));
      final source = File("${dir.path}/clip.mp4");
      await source.writeAsBytes(List.filled(250, 7));

      await seed(); // fileSize 300, 3 planned parts, s3UploadId=u1
      final coordinator = build(resolveFilePath: (_) async => source.path);

      final err = await coordinator.startSession("s1");

      expect(err, isNotNull);
      expect(err!.code, ErrorType.uploadInComplete);
      final session = (await dao.getSession("s1"))!;
      expect(session.state, SessionState.failedTerminal);
      expect(session.lastErrorCode, "fileSizeMismatch");
      expect(engine.began, isEmpty);
    },
  );

  test(
    "startSession begins normally when on-disk bytes match the frozen plan",
    () async {
      final dir = await Directory.systemTemp.createTemp("wuc_size_match");
      addTearDown(() => dir.delete(recursive: true));
      final source = File("${dir.path}/clip.mp4");
      await source.writeAsBytes(List.filled(300, 7));

      await seed(); // fileSize 300
      final coordinator = build(resolveFilePath: (_) async => source.path);

      final err = await coordinator.startSession("s1");

      expect(err, isNull);
      expect(engine.began, hasLength(1));
      expect(engine.began.first.fileUrl, source.path);
    },
  );

  group("adaptive transfer concurrency", () {
    // Drives one part's transfer through the tuner: a progress event anchors
    // the duration clock, the clock advances, the part completes.
    Future<void> transferPart(
      WindowedUploadCoordinator coordinator,
      int partNumber,
      void Function() advanceClock,
    ) async {
      await coordinator.applyEvent(
        WindowedProgress(
          "s1",
          partNumber: partNumber,
          bytesSent: 1,
          totalBytes: 100,
        ),
      );
      advanceClock();
      await coordinator.applyEvent(
        WindowedPartCompleted("s1", partNumber: partNumber, etag: "e$partNumber"),
      );
    }

    test("startSession arms the gate and pushes the initial level", () async {
      await seed();
      final err = await build().startSession("s1");
      expect(err, isNull);
      expect(
        engine.concurrencyPushes,
        [WindowedUploadCoordinator.initialTransferConcurrency],
      );
    });

    test("fast parts ramp the gate up to the max, one level per part", () async {
      await seed(parts: 8);
      // Chunk size is tiny (100 B) so the target time is the 8 s floor; 2 s
      // parts are comfortably "fast".
      var clock = DateTime.utc(2026, 7, 6, 12);
      final coordinator = build(clock: () => clock);
      await coordinator.startSession("s1");

      for (var n = 1; n <= 6; n++) {
        await transferPart(coordinator, n, () {
          clock = clock.add(const Duration(seconds: 2));
        });
      }

      // 6 at start, +1 per fast part until the ceiling, deduped after.
      expect(engine.concurrencyPushes, [6, 7, 8, 9, 10]);
    });

    test("slow parts back the gate off toward the floor", () async {
      await seed(parts: 8);
      // 20 s parts are > 1.5× the 8 s floor target — sustained slowness.
      var clock = DateTime.utc(2026, 7, 6, 12);
      final coordinator = build(clock: () => clock);
      await coordinator.startSession("s1");

      for (var n = 1; n <= 5; n++) {
        await transferPart(coordinator, n, () {
          clock = clock.add(const Duration(seconds: 20));
        });
      }

      // Decrease waits for 3 duration samples, then steps down and clamps at
      // the floor (5) — never below the user-facing minimum.
      expect(engine.concurrencyPushes.first, 6);
      expect(engine.concurrencyPushes.last, 5);
      expect(
        engine.concurrencyPushes.every(
          (level) =>
              level >= WindowedUploadCoordinator.minTransferConcurrency &&
              level <= WindowedUploadCoordinator.maxTransferConcurrency,
        ),
        isTrue,
      );
    });

    test(
      "completions without a progress anchor (Dart was frozen) don't move the gate",
      () async {
        await seed(parts: 8);
        final coordinator = build();
        await coordinator.startSession("s1");

        // Drained-journal replays / backgrounded completions arrive with no
        // preceding progress event — their wall-clock would be suspension-
        // inflated, so the tuner must not see them.
        for (var n = 1; n <= 6; n++) {
          await coordinator.applyEvent(
            WindowedPartCompleted("s1", partNumber: n, etag: "e$n"),
          );
        }

        expect(engine.concurrencyPushes, [6]);
      },
    );

    test(
      "non-congestion part failures leave the gate alone; congestion backs it off",
      () async {
        await seed(parts: 8);
        final coordinator = build(clock: () => DateTime.utc(2026, 7, 6, 12));
        await coordinator.startSession("s1");

        // urlExpired says nothing about the network.
        await coordinator.applyEvent(
          const WindowedPartFailed(
            "s1",
            partNumber: 1,
            errorCode: "urlExpired",
            httpStatus: 403,
          ),
        );
        // Our own cancellation isn't a network signal either.
        await coordinator.applyEvent(
          const WindowedPartFailed(
            "s1",
            partNumber: 2,
            errorCode: "cancelled",
          ),
        );
        expect(engine.concurrencyPushes, [6]);

        // Genuine congestion (timeouts) steps the gate down.
        await coordinator.applyEvent(
          const WindowedPartFailed(
            "s1",
            partNumber: 3,
            errorCode: "timeout",
          ),
        );
        expect(engine.concurrencyPushes, [6, 5]);
      },
    );
  });
}
