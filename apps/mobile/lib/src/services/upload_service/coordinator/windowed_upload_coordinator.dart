import "dart:async";
import "dart:convert";
import "dart:developer" as dev;
import "dart:io";

import "package:crypto/crypto.dart";
import "package:flutter/scheduler.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/schema/enums/upload_error_category.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/foreground_notification_service/foreground_notification_service.dart";
import "package:stera/src/services/upload_service/adaptive_concurrency_manager.dart";
import "package:stera/src/services/upload_service/channels/ios_windowed_uploader_service.dart";
import "package:stera/src/services/upload_service/diagnostics/upload_log.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_chunk_planner.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_chunk_sizer.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_disk_preflight.dart";
import "package:stera/src/services/upload_service/data/models/multipart_finalize_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";
import "package:stera/src/services/upload_service/data/repo/upload_repo.dart";
import "package:stera/src/services/upload_service/orchestrator/upload_orchestrator.dart";
import "package:stera/src/services/upload_service/presign/presign_manager.dart";
import "package:stera/src/services/upload_service/reconcile/upload_reconciler.dart";
import "package:stera/src/services/upload_service/retry/upload_error_classifier.dart";
import "package:stera/src/services/upload_service/retry/upload_retry_policy.dart";
import "package:stera/src/services/upload_service/utils/resolve_file_path.dart";

typedef FinalizeUploadFn =
    Future<(MultipartFinalizeResponse?, Failure?)> Function({
      required String key,
      required String uploadId,
      required int partCount,
    });

typedef RegisterAssetFn = Future<Failure?> Function(UploadSession session);

typedef StartMultipartFn =
    Future<(MultipartStartResponse?, Failure?)> Function({
      required String fileName,
      required String contentType,
      String? clientUploadId,
    });

typedef ResolveFilePathFn = Future<String> Function(String storedPath);

typedef FreeDiskBytesFn = Future<int> Function();

/// Ties the native windowed engine to the Dart orchestration: it feeds engine
/// events into the [UploadOrchestrator], answers the engine's URL requests via
/// [PresignManager], and finalizes via [UploadReconciler] + server-finalize.
/// This is the seam the live upload path uses on iOS.
///
/// Every dependency is injected with a singleton/real default (practice 04), so
/// the event glue is testable against an in-memory DB + a fake engine.
class WindowedUploadCoordinator {
  WindowedUploadCoordinator({
    UploadSessionDb? sessionDb,
    UploadOrchestrator? orchestrator,
    PresignManager? presignManager,
    UploadReconciler? reconciler,
    WindowedUploadEngine? engine,
    FinalizeUploadFn? finalizeUpload,
    RegisterAssetFn? registerAsset,
    StartMultipartFn? startMultipart,
    ResolveFilePathFn? resolveFilePath,
    FreeDiskBytesFn? freeDiskBytes,
    DateTime Function()? now,
    Future<void> Function(Duration delay)? wait,
    // In-flight window: how many chunk tasks the native daemon holds at once.
    // Only `httpMaximumConnectionsPerHost` (10) actually transfer in parallel;
    // the rest are a backlog the daemon advances through WITHOUT an app wake —
    // the key lever for sustained background/locked throughput (reqs 2 & 3).
    // Foregrounded, the adaptive gate (5–10, see [_concurrencyTuner]) keeps
    // in-flight below this. Disk cost is windowSize × chunkSize of temp files,
    // gated by the disk pre-flight.
    this.windowSize = 16,
  }) : _db = sessionDb ?? UploadSessionDb.instance,
       _now = now ?? DateTime.now,
       _orchestrator = orchestrator ?? UploadOrchestrator(sessionDb: sessionDb),
       _presign = presignManager ?? PresignManager(sessionDb: sessionDb),
       _reconciler = reconciler ?? UploadReconciler(sessionDb: sessionDb),
       _engine = engine ?? IosWindowedUploaderService.instance,
       _finalizeUpload = finalizeUpload ?? UploadRepo.finalizeMultipartUpload,
       _registerAsset = registerAsset ?? _defaultRegisterAsset,
       _startMultipart = startMultipart ?? UploadRepo.startMultipartUpload,
       _resolveFilePath = resolveFilePath ?? ResolveFilePath.resolve,
       _freeDiskBytes =
           freeDiskBytes ??
           (engine ?? IosWindowedUploaderService.instance).freeDiskBytes,
       _wait = wait ?? _defaultWait;

  /// App-wide instance, retained so its native event subscription (set up in
  /// [start]) lives for the process lifetime. The same instance also serves
  /// [startSession] calls from the upload service.
  static final WindowedUploadCoordinator instance = WindowedUploadCoordinator();

  final UploadSessionDb _db;
  final UploadOrchestrator _orchestrator;
  final PresignManager _presign;
  final UploadReconciler _reconciler;
  final WindowedUploadEngine _engine;
  final FinalizeUploadFn _finalizeUpload;
  final RegisterAssetFn _registerAsset;
  final StartMultipartFn _startMultipart;
  final ResolveFilePathFn _resolveFilePath;
  final FreeDiskBytesFn _freeDiskBytes;
  final DateTime Function() _now;
  final Future<void> Function(Duration delay) _wait;
  final int windowSize;

  static Future<void> _defaultWait(Duration delay) =>
      Future<void>.delayed(delay);

  /// Bounds for the adaptive foreground transfer-concurrency gate.
  static const int minTransferConcurrency = 5;
  static const int maxTransferConcurrency = 10;

  /// Starting gate — matches the native engine's built-in default (and the old
  /// fixed `httpMaximumConnectionsPerHost = 6` behavior) so an un-tuned session
  /// performs exactly like before.
  static const int initialTransferConcurrency = 6;

  /// AIMD tuner for how many part-PUTs native keeps in flight while the app is
  /// foregrounded (5–10). Same algorithm the legacy uploader used
  /// ([AdaptiveConcurrencyManager]): additive increase while parts land under
  /// the per-chunk target time, decrease when they run slow or fail — so the
  /// gate settles near `link bandwidth ÷ target per-part throughput`. Recreated
  /// per session in [_initTransferConcurrency] because the target time scales
  /// with that session's chunk size; the learned level carries over via
  /// [_pushedTransferConcurrency]. Backgrounded transfers are unaffected
  /// (native ignores the gate there), matching where the tuner can actually
  /// observe durations — progress events only flow while Dart is awake.
  AdaptiveConcurrencyManager? _concurrencyTuner;

  /// Last level pushed to native — dedupes channel calls and seeds the next
  /// session's tuner so network knowledge survives across uploads.
  int _pushedTransferConcurrency = initialTransferConcurrency;

  /// First-progress-event time per in-flight part ("sessionId#partNumber" →
  /// epoch ms), the start anchor for the tuner's per-part duration. A part with
  /// no entry completed while Dart was frozen (backgrounded/relaunched) — its
  /// wall-clock duration would be suspension-inflated, so it isn't fed.
  final Map<String, int> _partTransferStartMs = {};

  StreamSubscription<WindowedUploadEvent>? _eventSub;

  /// Sessions with an in-flight [startSession]. On cold start both
  /// [resumeOnLaunch] and the upload queue drive the same `legacy-<id>` session;
  /// this guard avoids redundant concurrent presign/begin round-trips. Native
  /// scheduling is already race-safe (claimNextSchedulablePart), so this is a
  /// pure efficiency guard, not a correctness one.
  final Set<String> _startingSessions = {};

  /// Subscribe to native engine events and resume any in-flight sessions. Call
  /// once at app start (iOS).
  Future<void> start() async {
    _eventSub ??= _engine.events().listen(applyEvent);
    await resumeOnLaunch();
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
  }

  /// Drain the native journal into the DB (results that arrived while Dart was
  /// dead), then reconcile + resume every active session. This is the explicit,
  /// ordered cold-start routine (doc 03 §4).
  Future<void> resumeOnLaunch() async {
    // Re-entrancy guard: this runs at cold start AND on every foreground resume
    // (app.dart), and both can overlap with the upload queue. Skip if a sync is
    // already in flight; per-session work below is independently idempotent.
    if (_resuming) {
      dev.log("resumeOnLaunch: already running (skipping)", name: "windowed");
      return;
    }
    _resuming = true;
    try {
      await _resumeOnLaunch();
    } finally {
      _resuming = false;
    }
  }

  bool _resuming = false;

  Future<void> _resumeOnLaunch() async {
    final (rows, err) = await _engine.drainJournal();
    if (err == null) {
      await _applyDrainedRows(rows);
      if (rows.isNotEmpty) {
        await _engine.acknowledgeDrain(rows);
      }
    }

    // Promote sessions whose parts all landed in the background.
    for (final session in await _db.getSessionsByStates([
      SessionState.transferring,
      SessionState.waitingRetry,
    ])) {
      final counts = await _db.partCounts(session.id);
      if (counts.total > 0 && counts.uploaded == counts.total) {
        await _db.setSessionState(session.id, SessionState.finalizing);
      }
    }

    // Repump URL runway for active transfers that may have stalled while dead.
    for (final session in await _db.getSessionsByStates([
      SessionState.transferring,
      SessionState.waitingRetry,
    ])) {
      await refreshUrls(session.id);
    }

    // Finalize sessions whose parts all landed in the background (the drain above
    // pushed them to `finalizing`) — they're fully transferred but not yet
    // registered, so drive them home.
    //
    // Crucially, do NOT begin `transferring`/`waitingRetry` sessions here. The
    // upload queue is the single, SEQUENTIAL transfer driver (uploadFile →
    // startSession → await terminal). Beginning every active session here too
    // piled them all onto one background URLSession at once, where they fought
    // over the per-host connection budget (4) and starved each other — so a 6 GB
    // upload monopolized the daemon and a freshly-queued clip never moved off 0%.
    // Letting the queue drive one at a time removes that contention; cold-start
    // resume still works because the queue is re-seeded from pending/uploading
    // rows on launch (UploadProvider._resumePendingUploadsOnStart).
    for (final state in [
      SessionState.finalizing,
      SessionState.registeringAsset,
    ]) {
      final sessions = await _db.getSessionsByStates([state]);
      for (final session in sessions) {
        await finalize(session.id);
      }
    }
  }

  Future<void> _applyDrainedRows(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      final sessionId = row["sessionId"] as String? ?? "";
      final partNumber = row["partNumber"] as int? ?? 0;
      switch (row["state"] as String?) {
        case "uploaded":
          await _orchestrator.recordPartCompleted(
            sessionId,
            partNumber,
            etag: row["etag"] as String? ?? "",
          );
        case "error":
          await _orchestrator.recordPartFailed(
            sessionId,
            partNumber,
            UploadErrorClassifier.classify(
              nativeErrorCode: row["errorCode"] as String?,
            ),
          );
      }
    }
  }

  /// Drive a session through the windowed engine: freeze the chunk plan,
  /// register the multipart upload (idempotent via clientUploadId = sessionId),
  /// presign the first window, and hand the manifest to native. Idempotent — on
  /// resume it skips already-done steps and only re-presigns + re-begins the
  /// pending parts.
  Future<Failure?> startSession(String sessionId) async {
    if (_startingSessions.contains(sessionId)) {
      dev.log(
        "startSession: already starting id=$sessionId (skipping duplicate)",
        name: "windowed",
      );
      return null;
    }
    _startingSessions.add(sessionId);
    try {
      return await _startSession(sessionId);
    } finally {
      _startingSessions.remove(sessionId);
    }
  }

  Future<Failure?> _startSession(String sessionId) async {
    var session = await _db.getSession(sessionId);
    if (session == null) {
      dev.log("startSession: NO SUCH SESSION id=$sessionId", name: "windowed");
      return Failure(message: "No such session", code: ErrorType.notFound);
    }
    UploadLog.add(
      "windowed",
      "startSession ENTER id=$sessionId state=${session.state} "
          "fileSize=${session.fileSize} s3UploadId=${session.s3UploadId} "
          "filepath=${session.filepath}",
    );

    // Already in a terminal state — never re-presign/begin/finalize (a repeat
    // finalize would re-register the asset). The watcher in the upload service
    // resolves the outcome from the session state; just no-op here.
    switch (session.state) {
      case SessionState.completed:
        return null;
      case SessionState.cancelled:
        return Failure(message: "Upload cancelled", code: ErrorType.cancelled);
      case SessionState.failedTerminal:
        return Failure(
          message: session.lastErrorDetail ?? "Upload failed",
          code: ErrorType.unknown,
        );
      default:
        break;
    }

    // ZERO-SIZE GUARD — a session with no bytes yields an EMPTY chunk plan
    // (partCount 0), which native drains instantly and the server finalize
    // then completes vacuously ("all 0 parts present"): the upload reads as
    // done with nothing in R2 and a 0s asset registered. Fail it loudly
    // instead; the row was created off a bad size snapshot and must be
    // removed and re-added.
    if (session.fileSize <= 0) {
      UploadLog.add(
        "windowed",
        "startSession ZERO-SIZE session=$sessionId fileSize=${session.fileSize} "
            "— failing terminally",
        level: UploadLogLevel.error,
      );
      await _db.markSessionFailed(
        sessionId,
        errorCode: "zeroFileSize",
        errorDetail:
            "This upload has no recorded file size. Remove it and re-add the "
            "recording.",
      );
      return Failure(
        message: "Recording has no file size — remove and re-add it.",
        code: ErrorType.uploadInComplete,
      );
    }

    // A session that already holds a server upload id is a *resume* (relaunch,
    // retry, or queue re-drive) — not a first run. Captured before the REGISTER
    // step below assigns one, so we only reconcile against storage when there's
    // actually a server upload to reconcile against.
    final isResume = session.s3UploadId != null;

    // Stable, recording-anchored idempotency key (NOT the autoincrement-derived
    // sessionId). A logout wipes the local Uploads journal, so on re-login the
    // same recording is re-added under a *new* `legacy-<id>` session — a row id
    // can't anchor resume. The mcap filepath is identical across the wipe +
    // re-add, so deriving the key from it lets the backend dedupe `/start` back
    // to the original multipart upload and we recover the parts already in R2.
    final clientUploadId = _clientUploadIdFor(session);

    // Set when REGISTER's /start deduped to a pre-existing upload. The local
    // journal is empty after a wipe, so the only way to learn which parts R2
    // already has is to reconcile — gate it on this just like a normal resume.
    var replayedStart = false;

    // DISK PRE-FLIGHT — the sliding window keeps at most `windowSize` chunk
    // temp files on disk, so we only need `windowSize × chunkSize` (+ one chunk
    // of slack) free, not a second copy of the whole file (doc 04 §4, T1).
    // Gate before we mutate any state / hit the network; leaves the session in
    // its current non-terminal state so the queue can retry once space frees.
    final preflightChunk =
        session.chunkSize ?? UploadChunkSizer.chooseChunkSize(session.fileSize);
    final freeBytes = await _freeDiskBytes();
    if (!UploadDiskPreflight.hasHeadroom(
      availableBytes: freeBytes,
      chunkSize: preflightChunk,
      windowSize: windowSize,
      slackBytes: preflightChunk,
    )) {
      final need = UploadDiskPreflight.requiredBytes(
        chunkSize: preflightChunk,
        windowSize: windowSize,
        slackBytes: preflightChunk,
      );
      dev.log(
        "startSession DISK-PREFLIGHT FAIL free=${freeBytes >> 20}MB "
        "need=${need >> 20}MB chunk=${preflightChunk >> 20}MB",
        name: "windowed",
      );
      return Failure(
        message:
            "Not enough free storage: need ~${need >> 20} MB free, have "
            "${freeBytes >> 20} MB.",
        code: ErrorType.insufficientStorage,
      );
    }

    // PREPARE — freeze the chunk plan once.
    if (session.chunkSize == null || session.partCount == null) {
      final chunkSize = UploadChunkSizer.chooseChunkSize(session.fileSize);
      final plan = UploadChunkPlanner.plan(
        fileSize: session.fileSize,
        chunkSize: chunkSize,
      );
      await _db.setServerIdentity(
        sessionId,
        chunkSize: chunkSize,
        partCount: plan.length,
      );
      await _db.insertParts([
        for (final e in plan)
          UploadPartsCompanion.insert(
            sessionId: sessionId,
            partNumber: e.partNumber,
            offset: e.offset,
            length: e.length,
          ),
      ]);
      session = (await _db.getSession(sessionId))!;
      dev.log(
        "startSession PLAN chunkSize=${chunkSize >> 20}MB partCount=${plan.length}",
        name: "windowed",
      );
    }

    // REGISTER — start the multipart upload once.
    if (session.s3UploadId == null) {
      await _db.setSessionState(sessionId, SessionState.registering);
      // clientUploadId is the stable, recording-anchored id for /start
      // idempotency. It need not be a UUID — the backend normalizes it (see
      // normalizeClientUploadId).
      dev.log(
        "startSession REGISTER -> /multipart/start "
        "fileName=${session.fileName} contentType=${session.mimeType} "
        "clientUploadId=$clientUploadId",
        name: "windowed",
      );
      final (start, err) = await _startMultipart(
        fileName: session.fileName,
        contentType: session.mimeType,
        clientUploadId: clientUploadId,
      );
      if (err != null || start == null) {
        dev.log(
          "startSession REGISTER FAIL err=${err?.code} msg=${err?.message}",
          name: "windowed",
        );
        return err ?? Failure(message: "start failed", code: ErrorType.unknown);
      }
      replayedStart = start.idempotentReplay;
      dev.log(
        "startSession REGISTER OK key=${start.key} uploadId=${start.uploadId} "
        "videoId=${start.videoId} idempotentReplay=$replayedStart",
        name: "windowed",
      );
      await _db.setServerIdentity(
        sessionId,
        s3Key: start.key,
        s3UploadId: start.uploadId,
        assetId: start.videoId,
      );
      session = (await _db.getSession(sessionId))!;
    }

    // RECONCILE ON RESUME — before re-presigning, diff local parts against what
    // R2 actually holds (ListParts). A part whose PUT *landed* just before a
    // force-quit cancelled its task is recorded server-side; the reconciler
    // adopts it so we never re-upload it (presign skips `uploaded` parts). This
    // recovers the maximum that is physically recoverable — S3 multipart parts
    // are atomic, so a part interrupted mid-PUT genuinely has to be re-sent.
    //
    // `replayedStart` covers the logout-wipe case: the local journal is gone, so
    // this is a "first run" by local state (isResume false), but /start deduped
    // to a pre-existing upload that already holds parts. Reconcile rebuilds the
    // part state from R2 so we resume instead of re-uploading from scratch.
    if (isResume || replayedStart) {
      final result = await _reconciler.reconcile(sessionId);
      UploadLog.add(
        "windowed",
        "startSession RECONCILE outcome=${result.outcome.name} "
            "adopted=${result.adopted} demoted=${result.demoted}",
      );
      session = (await _db.getSession(sessionId))!;

      switch (result.outcome) {
        case ReconcileOutcome.completedByServer:
          // The whole object is already on R2 (server auto-completed). Nothing
          // left to transfer — drive it home (finalize is idempotent).
          await finalize(sessionId);
          return null;
        case ReconcileOutcome.restartRequired:
          // The multipart is gone and no object exists. Re-register, getting a
          // brand-new uploadId (the backend mints a fresh one once its stored
          // mapping is dead — otherwise it'd keep replaying the same dead id).
          final (start, err) = await _startMultipart(
            fileName: session.fileName,
            contentType: session.mimeType,
            clientUploadId: clientUploadId,
          );
          if (err != null || start == null) {
            return err ??
                Failure(message: "re-register failed", code: ErrorType.unknown);
          }
          await _db.setServerIdentity(
            sessionId,
            s3Key: start.key,
            s3UploadId: start.uploadId,
            assetId: start.videoId,
          );
          // The uploadId changed, so EVERY part's URL/ETag (signed for the old,
          // now-dead upload) is invalid. Reset them all so the presign below
          // re-signs against the fresh upload — otherwise parts re-PUT to the
          // dead id and 404 forever.
          await _db.resetAllPartsForRestart(sessionId);
          session = (await _db.getSession(sessionId))!;
        case ReconcileOutcome.reconciled:
          // Adoption may have completed the last missing parts — if everything
          // is now uploaded, finalize instead of beginning native with no work.
          final counts = await _db.partCounts(sessionId);
          if (counts.total > 0 && counts.uploaded == counts.total) {
            await _db.setSessionState(sessionId, SessionState.finalizing);
            await finalize(sessionId);
            return null;
          }
        case ReconcileOutcome.failed:
        case ReconcileOutcome.skipped:
          // Transient ListParts failure (or nothing to anchor against) — proceed
          // with the normal resume; finalize reconciles again at the end.
          break;
      }
    }

    await _db.setSessionState(sessionId, SessionState.transferring);

    // Fresh begin for this session — clear any prior needUrls stall counter.
    _needUrlsNoProgress.remove(sessionId);

    // Arm the adaptive concurrency gate for this session's chunk size and
    // (re-)push the level — the native gate is process-lifetime, so an engine
    // relaunched since the last push is back at its default until told again.
    await _initTransferConcurrency(session.chunkSize!);

    // Presign the full runway before handing the session to native. Native is
    // intentionally backend-agnostic; once Dart is suspended it cannot answer
    // `needUrls`, so BEGIN must carry every currently needed URL.
    final (_, presignErr) = await _ensureAllUrls(sessionId);
    if (presignErr != null) {
      UploadLog.add(
        "windowed",
        "startSession PRESIGN FAIL err=${presignErr.code} msg=${presignErr.message}",
        level: UploadLogLevel.error,
      );
      return presignErr;
    }

    // BEGIN on native with the resolved absolute path + the fully signed runway.
    final resolvedPath = await _resolveFilePath(session.filepath);

    // SIZE-MISMATCH GUARD — the chunk plan is frozen from session.fileSize,
    // so if the file on disk holds a different byte count the plan covers a
    // truncated prefix (row snapshotted while native finalization was still
    // writing) or trails past EOF. Either way the object could "complete"
    // while never matching the recording — fail terminally instead. Skipped
    // when the file can't be statted (e.g. unit tests' fake paths); a truly
    // missing file fails at native BEGIN with per-part file errors.
    final onDiskLength = await _statFileLength(resolvedPath);
    if (onDiskLength != null && onDiskLength != session.fileSize) {
      UploadLog.add(
        "windowed",
        "startSession SIZE-MISMATCH session=$sessionId "
            "planned=${session.fileSize} onDisk=$onDiskLength — failing "
            "terminally",
        level: UploadLogLevel.error,
      );
      await _engine.cancelSession(sessionId);
      await _db.markSessionFailed(
        sessionId,
        errorCode: "fileSizeMismatch",
        errorDetail:
            "The recording on disk (${onDiskLength >> 20} MB) does not match "
            "this upload's plan (${session.fileSize >> 20} MB). Remove this "
            "upload and re-add the recording.",
      );
      return Failure(
        message:
            "Recording file changed since this upload was added — remove it "
            "and re-add the recording.",
        code: ErrorType.uploadInComplete,
      );
    }

    final pending = await _db.getPendingParts(sessionId);
    final ready = pending
        .where((p) => p.state == PartState.urlReady && p.url != null)
        .map(
          (p) => WindowedPartPlan(
            partNumber: p.partNumber,
            offset: p.offset,
            length: p.length,
            url: p.url!,
            urlExpiresAt: p.urlExpiresAt,
          ),
        )
        .toList();

    UploadLog.add(
      "windowed",
      "startSession BEGIN -> native resolvedPath=$resolvedPath "
          "pending=${pending.length} ready=${ready.length} "
          "firstPart=${ready.isEmpty ? "none" : ready.first.partNumber}",
    );
    final beginErr = await _engine.beginSession(
      WindowedSessionManifest(
        sessionId: sessionId,
        fileUrl: resolvedPath,
        contentType: session.mimeType,
        fileSize: session.fileSize,
        chunkSize: session.chunkSize!,
        windowSize: windowSize,
        parts: ready,
      ),
    );
    UploadLog.add(
      "windowed",
      "startSession BEGIN result=${beginErr == null ? "OK" : "FAIL ${beginErr.code} ${beginErr.message}"}",
      level: beginErr == null ? UploadLogLevel.info : UploadLogLevel.error,
    );
    if (beginErr != null) return beginErr;

    return null;
  }

  /// Byte length of the file at [resolvedPath], or null when it can't be
  /// statted (missing file, sandbox path from a test fake). Null means "can't
  /// verify" — callers must not treat it as a mismatch.
  Future<int?> _statFileLength(String resolvedPath) async {
    try {
      final file = File(resolvedPath);
      if (!await file.exists()) return null;
      return await file.length();
    } catch (_) {
      // Unstattable path — verification is best-effort; native BEGIN is the
      // authority on readability.
      return null;
    }
  }

  /// Presign every pending part and push fresh URLs to native. Returns a
  /// [Failure] if presigning fails; null on success (including when nothing
  /// needed signing).
  Future<Failure?> refreshUrls(String sessionId) async {
    final (_, err) = await _ensureAllUrls(sessionId);
    if (err != null) return err;
    return _provideReadyParts(sessionId);
  }

  /// Push every not-yet-uploaded part that currently holds a fresh URL to the
  /// native engine.
  Future<Failure?> _provideReadyParts(String sessionId) async {
    final pending = await _db.getPendingParts(sessionId);
    final ready = pending
        .where((p) => p.state == PartState.urlReady && p.url != null)
        .map(
          (p) => WindowedPartPlan(
            partNumber: p.partNumber,
            offset: p.offset,
            length: p.length,
            url: p.url!,
            urlExpiresAt: p.urlExpiresAt,
          ),
        )
        .toList();

    if (ready.isNotEmpty) {
      final provideErr = await _engine.provideUrls(sessionId, ready);
      if (provideErr != null) return provideErr;
    }
    return null;
  }

  /// How many consecutive `needUrls` rounds may presign **zero** new URLs before
  /// we treat the session as wedged. The native engine re-asks within
  /// milliseconds, so a genuine stall — every part already presigned yet native
  /// still can't fill its window (a chunk-plan / part-accounting desync) —
  /// otherwise spins forever, pinning the CPU and flooding the log. Reached in
  /// well under a second of looping; reset on any real progress.
  static const int _maxNoProgressNeedUrls = 12;

  /// Per-session count of consecutive no-progress `needUrls` rounds.
  final Map<String, int> _needUrlsNoProgress = {};

  /// Answer a native `needUrls`: presign what's missing and push it over. If a
  /// round presigns nothing new, count it; after [_maxNoProgressNeedUrls] such
  /// rounds the session is wedged (native wants parts Dart can't presign), so
  /// break the loop and fail it loudly instead of spinning.
  Future<void> _handleNeedUrls(String sessionId) async {
    final (assigned, err) = await _ensureAllUrls(sessionId);
    if (err == null) await _provideReadyParts(sessionId);

    // Real progress (new URLs) or a transient error we'll retry — not a stall.
    if (assigned > 0 || err != null) {
      _needUrlsNoProgress.remove(sessionId);
      return;
    }

    final n = (_needUrlsNoProgress[sessionId] ?? 0) + 1;
    _needUrlsNoProgress[sessionId] = n;
    if (n < _maxNoProgressNeedUrls) return;

    _needUrlsNoProgress.remove(sessionId);
    UploadLog.add(
      "windowed",
      "NEED-URLS stall: native requested URLs ${n}x but every part already had "
          "one — breaking the loop and failing session=$sessionId "
          "(chunk-plan/part desync)",
      level: UploadLogLevel.error,
    );
    await _engine.cancelSession(sessionId);
    await _db.markSessionFailed(
      sessionId,
      errorCode: "needUrlsStall",
      errorDetail:
          "Upload stalled: the uploader kept requesting upload links but every "
          "part already had one. Remove this upload and re-add the recording.",
    );
  }

  /// (Re)create the concurrency tuner for a session whose chunk plan is frozen
  /// and push the current gate to native. The tuner is per-session because its
  /// per-part target time scales with the chunk size; the learned level itself
  /// carries over through [_pushedTransferConcurrency].
  Future<void> _initTransferConcurrency(int chunkSize) async {
    _concurrencyTuner = AdaptiveConcurrencyManager(
      minConcurrency: minTransferConcurrency,
      maxConcurrency: maxTransferConcurrency,
      targetUploadTimeMs: _targetPartTimeMs(chunkSize),
      initialConcurrency: _pushedTransferConcurrency.clamp(
        minTransferConcurrency,
        maxTransferConcurrency,
      ),
    );
    await _pushTransferConcurrency(force: true);
  }

  /// Per-part target duration scaled to [chunkSize]: ~6 Mbps effective
  /// per-part throughput (the tuner's original calibration of 40 s per 30 MiB),
  /// floored at 8 s so small chunks don't flap the gate on ordinary latency
  /// jitter. Parts consistently slower than 1.5× this back the gate off; parts
  /// consistently faster ramp it up.
  static int _targetPartTimeMs(int chunkSize) {
    const msPer30MiB = 40000;
    final scaled = chunkSize * msPer30MiB ~/ (30 * 1024 * 1024);
    return scaled < 8000 ? 8000 : scaled;
  }

  /// Record one finished transfer with the tuner and push the gate to native
  /// if the level moved. Successful parts need an honest wall-clock duration
  /// (their [_partTransferStartMs] anchor); a success without one finished
  /// while Dart was frozen and is skipped. Failures carry their signal in the
  /// failure itself, so they feed regardless.
  Future<void> _feedConcurrencyTuner(
    String sessionId,
    int partNumber, {
    required bool success,
  }) async {
    final startMs = _partTransferStartMs.remove("$sessionId#$partNumber");
    final tuner = _concurrencyTuner;
    if (tuner == null) return;
    if (success && startMs == null) return;
    final durationMs = startMs == null
        ? 0
        : _now().millisecondsSinceEpoch - startMs;
    tuner.onChunkComplete(success, durationMs);
    await _pushTransferConcurrency();
  }

  /// Push the tuner's current level over the channel, deduped against the last
  /// push. A failed push is non-fatal: native keeps its previous gate and the
  /// next adjustment retries.
  Future<void> _pushTransferConcurrency({bool force = false}) async {
    final level = _concurrencyTuner?.concurrency;
    if (level == null) return;
    if (!force && level == _pushedTransferConcurrency) return;
    _pushedTransferConcurrency = level;
    UploadLog.add("windowed", "transfer concurrency -> $level");
    final err = await _engine.setTransferConcurrency(maxInFlight: level);
    if (err != null) {
      UploadLog.add(
        "windowed",
        "setTransferConcurrency FAIL err=${err.code} msg=${err.message}",
        level: UploadLogLevel.warn,
      );
    }
  }

  /// Apply one native engine event — the runtime glue between native transfer
  /// results and the Dart state machine.
  Future<void> applyEvent(WindowedUploadEvent event) async {
    switch (event) {
      case WindowedPartCompleted(
        :final sessionId,
        :final partNumber,
        :final etag,
      ):
        UploadLog.add(
          "windowed",
          "event PART-COMPLETED session=$sessionId part=$partNumber etag=$etag",
        );
        final state = await _orchestrator.recordPartCompleted(
          sessionId,
          partNumber,
          etag: etag,
        );
        // Real progress — clear any needUrls stall counter for this session.
        _needUrlsNoProgress.remove(sessionId);
        await _feedConcurrencyTuner(sessionId, partNumber, success: true);
        // The part's bytes are now counted in uploadedBytes — drop it from the
        // in-flight tally and push a durable progress update (force = bypass the
        // throttle, a completed part is a meaningful step).
        _inFlightBytes[sessionId]?.remove(partNumber);
        await _reportProgress(sessionId, force: true);
        if (state == SessionState.finalizing) await finalize(sessionId);

      case WindowedPartFailed(
        :final sessionId,
        :final partNumber,
        :final errorCode,
      ):
        final category = UploadErrorClassifier.classify(
          nativeErrorCode: errorCode,
        );
        final action = await _orchestrator.recordPartFailed(
          sessionId,
          partNumber,
          category,
        );
        // Congestion-shaped failures back the concurrency gate off; anything
        // else (expired URL, file/disk/auth errors) says nothing about the
        // network, and cancellation "failures" are just our own teardown —
        // for those only the stale start anchor is dropped.
        const congestionCategories = {
          UploadErrorCategory.network,
          UploadErrorCategory.timeout,
          UploadErrorCategory.serverError,
          UploadErrorCategory.throttled,
        };
        final isCancellation =
            errorCode == "cancelled" || errorCode == "userForceQuit";
        if (congestionCategories.contains(category) && !isCancellation) {
          await _feedConcurrencyTuner(sessionId, partNumber, success: false);
        } else {
          _partTransferStartMs.remove("$sessionId#$partNumber");
        }
        _inFlightBytes[sessionId]?.remove(partNumber);
        UploadLog.add(
          "windowed",
          "event PART-FAILED session=$sessionId part=$partNumber "
              "errorCode=$errorCode category=$category action=${action.kind}",
          level: UploadLogLevel.warn,
        );
        if (action.kind == PartRetryKind.refreshUrl) {
          await refreshUrls(sessionId);
        } else if (action.kind == PartRetryKind.retry) {
          unawaited(
            _requeuePartAfterBackoff(
              sessionId,
              partNumber,
              action.delay ?? Duration.zero,
            ),
          );
        }

      case WindowedNeedUrls(:final sessionId):
        UploadLog.add("windowed", "event NEED-URLS session=$sessionId");
        await _handleNeedUrls(sessionId);

      case WindowedSessionDrained(:final sessionId):
        UploadLog.add("windowed", "event SESSION-DRAINED session=$sessionId");
        await finalize(sessionId);

      case WindowedProgress(
        :final sessionId,
        :final partNumber,
        :final bytesSent,
        :final totalBytes,
      ):
        // First progress event for a part anchors the tuner's duration clock.
        _partTransferStartMs.putIfAbsent(
          "$sessionId#$partNumber",
          () => _now().millisecondsSinceEpoch,
        );
        // Track the in-flight byte count for this part so _reportProgress can
        // turn partial-part bytes into a smooth, durable per-row progress value
        // for EVERY session — not just the one the queue happens to be awaiting
        // (that gap is why a second/just-started upload's tile sat at 0% while
        // it was actually transferring).
        (_inFlightBytes[sessionId] ??= {})[partNumber] = bytesSent;
        await _reportProgress(sessionId);

        // Throttled log so the dev page can confirm bytes are actually moving —
        // the difference between "uploading slowly" and "stalled".
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - (_lastProgressLogMs[sessionId] ?? 0) >= 3000) {
          _lastProgressLogMs[sessionId] = nowMs;
          UploadLog.add(
            "windowed",
            "event PROGRESS session=$sessionId part=$partNumber "
                "sent=${bytesSent >> 20}/${totalBytes >> 20}MB",
            level: UploadLogLevel.debug,
          );
        }
    }
  }

  /// Re-push one part to native after a `retry` decision's backoff. An
  /// HTTP-rejected part is parked in the native journal (`error`) and native
  /// never reschedules it on its own — the only transition back to `planned` is
  /// a manifest upsert pushed from Dart. Without this re-push the policy's
  /// "retry same URL after backoff" was a dead letter: the part sat parked
  /// until the needUrls stall breaker failed the whole session, and a single
  /// transient 5xx could wedge an upload permanently. Skips silently when the
  /// session left `transferring` during the wait (completed/failed/cancelled —
  /// those paths own the journal then) or the part moved on (uploaded, or
  /// demoted for a URL refresh, which re-pushes it itself).
  Future<void> _requeuePartAfterBackoff(
    String sessionId,
    int partNumber,
    Duration delay,
  ) async {
    if (delay > Duration.zero) await _wait(delay);
    final session = await _db.getSession(sessionId);
    if (session == null || session.state != SessionState.transferring) return;

    final parts = await _db.getParts(sessionId);
    final matches = parts.where((p) => p.partNumber == partNumber).toList();
    if (matches.isEmpty) return;
    final part = matches.first;
    if (part.state != PartState.urlReady || part.url == null) return;

    UploadLog.add(
      "windowed",
      "requeue part after backoff session=$sessionId part=$partNumber "
          "delay=${delay.inMilliseconds}ms",
    );
    final err = await _engine.provideUrls(sessionId, [
      WindowedPartPlan(
        partNumber: part.partNumber,
        offset: part.offset,
        length: part.length,
        url: part.url!,
        urlExpiresAt: part.urlExpiresAt,
      ),
    ]);
    if (err != null) {
      // Non-fatal: the engine's next needUrls round re-provides ready parts.
      UploadLog.add(
        "windowed",
        "requeue provideUrls FAIL err=${err.code} msg=${err.message}",
        level: UploadLogLevel.warn,
      );
    }
  }

  /// Last time (epoch ms) a PROGRESS line was logged for a session — throttles
  /// the per-byte progress flood to ~one line / 3s / session in the dev log.
  final Map<String, int> _lastProgressLogMs = {};

  /// Per-session, per-part in-flight byte counts (latest `bytesSent` from native
  /// progress events). Summed with `uploadedBytes` to derive overall progress.
  final Map<String, Map<int, int>> _inFlightBytes = {};

  /// Monotonic last-written progress fraction per session, so a durable write
  /// never moves a tile backward and we skip no-op writes.
  final Map<String, double> _lastReportedFraction = {};

  /// Throttle for the durable progress write (DB) per session.
  final Map<String, int> _lastProgressWriteMs = {};

  /// Write a durable progress fraction (0..1) onto the legacy `Uploads` row for
  /// [sessionId], computed from completed + in-flight bytes. This is the single
  /// progress source that works for ALL active sessions (the queue's live bridge
  /// only covers the one upload it's awaiting). Monotonic + throttled; [force]
  /// bypasses the throttle (used on part completion). Non-`legacy-` sessions and
  /// zero-size sessions are ignored.
  Future<void> _reportProgress(String sessionId, {bool force = false}) async {
    const prefix = "legacy-";
    if (!sessionId.startsWith(prefix)) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && nowMs - (_lastProgressWriteMs[sessionId] ?? 0) < 700) return;

    final session = await _db.getSession(sessionId);
    if (session == null || session.fileSize <= 0) return;

    final completed = await _db.uploadedBytes(sessionId);
    final inflight =
        _inFlightBytes[sessionId]?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    final fraction = ((completed + inflight) / session.fileSize).clamp(
      0.0,
      1.0,
    );

    final last = _lastReportedFraction[sessionId];
    if (last != null && fraction <= last) return; // monotonic / no-op

    _lastReportedFraction[sessionId] = fraction;
    _lastProgressWriteMs[sessionId] = nowMs;

    final id = int.tryParse(sessionId.substring(prefix.length));
    if (id == null) return;
    await UploadDb.instance.updateProgress(id, fraction);
  }

  /// Presign every part that currently needs a (fresh) URL, in bounded batches,
  /// until none remain. Each [PresignManager.ensureUrls] call signs one batch
  /// and returns how many it assigned; we loop until it assigns zero (all
  /// pending parts now hold fresh URLs) or hits a [Failure]. The iteration cap
  /// covers R2's 10k-part ceiling at the 256-part batch size while bounding the
  /// burst of requests at session start.
  Future<(int, Failure?)> _ensureAllUrls(String sessionId) async {
    const maxBatches = 64;
    var total = 0;
    for (var i = 0; i < maxBatches; i++) {
      final (count, err) = await _presign.ensureUrls(sessionId);
      if (err != null) return (total, err);
      total += count;
      if (count == 0) break; // every pending part now has a fresh URL
    }
    dev.log(
      "ensureAllUrls session=$sessionId assigned=$total",
      name: "windowed",
    );
    return (total, null);
  }

  /// Reconcile against storage truth, then ask the backend to finalize
  /// server-side; register the asset and mark the session complete on success.
  /// Idempotent and safe to re-enter (each step is a guarded DB transition).
  Future<void> finalize(String sessionId) async {
    UploadLog.add("windowed", "finalize ENTER session=$sessionId");
    await _reconciler.reconcile(sessionId);

    final session = await _db.getSession(sessionId);
    if (session == null) return;
    // Reconciler demoted to `registering` → the start flow must re-register.
    if (session.state == SessionState.registering) {
      UploadLog.add(
        "windowed",
        "finalize ABORT: reconciler demoted to registering session=$sessionId",
        level: UploadLogLevel.warn,
      );
      return;
    }

    final key = session.s3Key;
    final uploadId = session.s3UploadId;
    final partCount = session.partCount;
    if (key == null || uploadId == null || partCount == null) {
      UploadLog.add(
        "windowed",
        "finalize ABORT: missing identity key=$key uploadId=$uploadId partCount=$partCount",
        level: UploadLogLevel.warn,
      );
      return;
    }

    // ZERO-PART GUARD — never ask the server to finalize an empty plan. A
    // backend that checks "storage holds all partCount parts" passes
    // vacuously for 0, so the session would complete and register a 0s asset
    // with nothing in R2. Sessions like this exist only from a bad size
    // snapshot; fail them terminally.
    if (partCount <= 0) {
      UploadLog.add(
        "windowed",
        "finalize ZERO-PARTS session=$sessionId partCount=$partCount — "
            "failing terminally instead of finalizing vacuously",
        level: UploadLogLevel.error,
      );
      await _db.markSessionFailed(
        sessionId,
        errorCode: "zeroPartCount",
        errorDetail:
            "This upload planned zero parts (empty file size snapshot). "
            "Remove it and re-add the recording.",
      );
      return;
    }

    await _db.setSessionState(sessionId, SessionState.finalizing);
    UploadLog.add(
      "windowed",
      "finalize -> /multipart/finalize key=$key partCount=$partCount",
    );
    final (resp, err) = await _finalizeUpload(
      key: key,
      uploadId: uploadId,
      partCount: partCount,
    );
    if (err != null || resp == null || !resp.completed) {
      UploadLog.add(
        "windowed",
        "finalize INCOMPLETE err=${err?.code} msg=${err?.message} "
            "completed=${resp?.completed} (will retry)",
        level: UploadLogLevel.warn,
      );
      _notifyForegroundFinalizeNeeded(
        sessionId,
        reason: err?.code.name ?? "incomplete",
      );
      return; // retry later (resumeOnLaunch re-drives on next foreground)
    }

    await _db.setSessionState(sessionId, SessionState.registeringAsset);
    UploadLog.add("windowed", "finalize -> registerAsset session=$sessionId");
    final assetErr = await _registerAsset(session);
    if (assetErr != null) {
      UploadLog.add(
        "windowed",
        "finalize REGISTER-ASSET FAIL err=${assetErr.code} msg=${assetErr.message} (will retry)",
        level: UploadLogLevel.warn,
      );
      _notifyForegroundFinalizeNeeded(sessionId, reason: assetErr.code.name);
      return; // retry later
    }

    await _db.setSessionState(sessionId, SessionState.completed);
    await _completeLegacyRow(sessionId);
    // The upload is fully done (asset registered), so forget the native journal
    // session. Otherwise its now-stale `drained` row lingers forever — native
    // only deletes session rows on user-cancel — and `videoCounts()` counts
    // every non-cancelled session for the background progress notification's
    // "X/Y" tally. Left behind, finished uploads from earlier in the run make a
    // lone in-flight video read as e.g. "4/6 (75%)" instead of "1/1 (75%)".
    // cancelSession just tears down the journal rows here; a finalized session
    // has no in-flight tasks left to cancel.
    await _engine.cancelSession(sessionId);
    // Drop per-session bookkeeping so a reused id starts clean.
    _finalizeNotifiedSessions.remove(sessionId);
    _partTransferStartMs.removeWhere((key, _) => key.startsWith("$sessionId#"));
    _inFlightBytes.remove(sessionId);
    _lastReportedFraction.remove(sessionId);
    _lastProgressWriteMs.remove(sessionId);
    _lastProgressLogMs.remove(sessionId);
    UploadLog.add("windowed", "finalize COMPLETED session=$sessionId");
  }

  /// Sessions that already received a "open the app to finish" notification.
  final Set<String> _finalizeNotifiedSessions = {};

  /// When finalize/register cannot complete while backgrounded, post a single
  /// local notification asking the user to reopen the app.
  void _notifyForegroundFinalizeNeeded(
    String sessionId, {
    required String reason,
  }) {
    AppLifecycleState? lifecycle;
    try {
      lifecycle = SchedulerBinding.instance.lifecycleState;
    } catch (_) {
      // No Flutter binding (e.g. pure unit tests) — skip notification.
      return;
    }
    final isForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (isForeground) return;
    if (!_finalizeNotifiedSessions.add(sessionId)) return;
    UploadLog.add(
      "windowed",
      "finalize blocked while backgrounded ($reason) — notifying user to reopen",
      level: UploadLogLevel.warn,
    );
    unawaited(
      ForegroundNotificationService.showNotification(
        title: "Almost done!",
        body: "Open the app to finish uploading your video.",
      ),
    );
  }

  /// Mirror the completed session onto its legacy `Uploads` row. The queue path
  /// ([UploadsService._uploadViaWindowedEngine]) already does this, but a session
  /// finalized directly by [resumeOnLaunch] (the `finalizing` branch on cold
  /// start) would otherwise leave the row `pending` — the queue then re-seeds it
  /// and loops. Idempotent: `updateStatus` is a single column write. Keyed on the
  /// `legacy-<id>` session id the upload path uses; other ids are ignored.
  Future<void> _completeLegacyRow(String sessionId) async {
    const prefix = "legacy-";
    if (!sessionId.startsWith(prefix)) return;
    final id = int.tryParse(sessionId.substring(prefix.length));
    if (id == null) return;
    await UploadDb.instance.updateStatus(id, UploadStatus.completed);
    UploadLog.add("windowed", "finalize marked legacy upload $id completed");
  }

  /// The stable, recording-anchored idempotency key for `/multipart/start`.
  ///
  /// Derived from the mcap [UploadSession.filepath] (a documents-relative URI
  /// that `recoverOrphanedSessions` reconstructs identically for the same
  /// recording), NOT from the autoincrement-derived `sessionId`. A logout wipes
  /// the local Uploads journal and re-adds the recording under a fresh row id;
  /// hashing the filepath gives the *same* key across that wipe, so the backend
  /// dedupes `/start` back to the original multipart upload and we resume from
  /// R2 instead of re-uploading. SHA-256 keeps it opaque and ≤200 chars (the
  /// backend then normalizes it to a UUIDv5).
  ///
  /// [fileSize] is mixed in to avoid a cross-device collision: the recording
  /// folder is `session_<second-precision-ts>_<deviceModel>`, so two phones of
  /// the same model that start recording in the same wall-clock second produce
  /// the same path. The backend dedupes per `(profileId, clientUploadId)`, so
  /// that only matters when both devices share an account — but there it would
  /// merge two different recordings into one object. The exact byte size differs
  /// between any two real recordings, so it disambiguates them. (For a zero-
  /// residual key, embed a per-recording UUID at capture time and hash that.)
  String _clientUploadIdFor(UploadSession session) =>
      "rec-${sha256.convert(utf8.encode("${session.filepath}:${session.fileSize}"))}";

  static Future<Failure?> _defaultRegisterAsset(UploadSession s) async {
    return UploadRepo.registerAsset(
      storagePath: s.s3Key ?? "",
      filename: s.fileName,
      durationSeconds: (s.durationMs ?? 0) ~/ 1000,
      thumbnailFilePath: s.thumbnailPath,
      mimeType: s.mimeType,
      fileSizeBytes: s.fileSize,
      metadata: await _loadMetadata(s.metadataFilepath),
    );
  }

  /// Reads and parses the recording's metadata JSON (poses/depth/etc. summary)
  /// so the registered asset carries it — parity with the legacy complete path
  /// (`utils/complete_multipart_upload.dart`). Best-effort: a missing/bad file
  /// just omits metadata rather than failing the upload.
  static Future<Map<String, dynamic>?> _loadMetadata(
    String? metadataFilepath,
  ) async {
    if (metadataFilepath == null || metadataFilepath.isEmpty) return null;
    try {
      final resolved = await ResolveFilePath.resolve(metadataFilepath);
      final file = File(resolved);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (e) {
      dev.log("windowed: failed to load upload metadata: $e", name: "windowed");
    }
    return null;
  }
}
