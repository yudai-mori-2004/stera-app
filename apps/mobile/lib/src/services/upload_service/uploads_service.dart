import "dart:async";
import "dart:io";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/modules/upload_estimate/services/upload_speed_tracker.dart";
import "package:drift/drift.dart" show Value;
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/upload_service/coordinator/windowed_upload_coordinator.dart";
import "package:stera/src/services/upload_service/channels/ios_windowed_uploader_service.dart";
import "package:stera/src/services/upload_service/data/typedef/upload_progress.dart";
import "package:stera/src/services/upload_service/diagnostics/upload_log.dart";
import "package:stera/src/services/upload_service/utils/mcap_finalization.dart";
import "package:stera/src/services/upload_service/utils/resolve_file_path.dart";
import "package:rxdart/rxdart.dart";

/// Service responsible for managing uploads to S3 using multipart upload.
///
/// This service handles:
/// - Starting multipart uploads with the backend
/// - Fetching presigned URLs for each chunk
/// - Uploading chunks concurrently with adaptive concurrency
/// - Resuming failed/interrupted uploads
/// - Completing or aborting multipart uploads
///
/// Uses a singleton pattern to ensure only one upload process runs at a time.
///
/// ## Upload Flow:
/// 1. Prepare upload (validate, get metadata)
/// 2. Start multipart upload → get uploadId and S3 key
/// 3. Get presigned URLs for all parts
/// 4. Upload chunks with adaptive concurrency
/// 5. Complete S3 upload
/// 6. Create video record
/// 7. Mark upload as completed
/// 8. Cleanup local files
///
/// ## Resume Support:
/// - Stores multipartStartResponse, partUrls, and uploadedParts in DB
/// - On resume, skips already completed steps and continues from last position

class UploadsService {
  UploadsService._internal() {
    _progressSubject.listen(_trackProgressMilestone);
  }

  static final UploadsService _instance = UploadsService._internal();
  static UploadsService get instance => _instance;

  UploadDb get db => UploadDb.instance;

  /// BehaviorSubject for upload progress - late subscribers get the last value.
  /// Seeded with null to indicate no upload in progress.
  final _progressSubject = BehaviorSubject<UploadProgress?>.seeded(null);

  /// Stream of upload progress updates.
  /// Emits null when no upload is in progress, or the current progress.
  Stream<UploadProgress?> get progressStream => _progressSubject.stream;

  /// Current upload progress, or null if no upload is in progress.
  UploadProgress? get currentProgress => _progressSubject.valueOrNull;

  bool _isCancelled = false;

  /// Whether uploads are paused. When true, the upload will stop after
  /// the current batch of chunks completes.
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// Completer that resolves when cancellation is fully processed.
  Completer<void>? _cancelCompleter;

  /// Whether an upload is currently in progress.
  bool _isUploading = false;

  /// The windowed-engine session id for the in-flight iOS upload (so cancel can
  /// reach it). Null when no windowed upload is running.
  String? _activeWindowedSessionId;
  StreamSubscription<UploadSession?>? _windowedWatchSub;
  StreamSubscription<WindowedUploadEvent>? _windowedProgressSub;

  Upload? _analyticsCurrentUpload;
  final Map<int, Set<int>> _analyticsProgressMilestones = {};

  /// Request the upload to pause after current chunks complete.
  /// This doesn't immediately stop the upload - it signals that after
  /// the current batch of chunks finishes, the upload should stop.
  void requestPause() => _isPaused = true;

  /// Clear the pause flag to allow uploads to continue.
  void clearPause() => _isPaused = false;

  /// Clear the progress stream, signaling no upload is in progress.
  /// Used when cancelling all uploads to ensure UI updates correctly.
  void clearProgress() => _progressSubject.add(null);

  /// Tears down the windowed (iOS) upload session for [uploadId] — call when an
  /// upload is **deleted/removed** so a removed file stops uploading in the
  /// background. Cancels any in-flight native `URLSession` tasks and deletes the
  /// native journal session (via the engine's `cancelSession`), then removes the
  /// local session + part rows. Safe on Android / when no session exists (no-op
  /// cancel + delete of nothing). Keyed on the same `legacy-<id>` session id the
  /// upload path uses.
  Future<void> cancelWindowedSessionFor(int uploadId) async {
    final sessionId = "legacy-$uploadId";
    if (_activeWindowedSessionId == sessionId) _isCancelled = true;
    await IosWindowedUploaderService.instance.cancelSession(sessionId);
    await UploadSessionDb.instance.deleteSession(sessionId);
  }

  /// Cancels the current upload and returns a Future that completes
  /// when the cancellation is fully processed.
  ///
  /// If no upload is in progress, returns immediately.
  Future<void> cancelCurrentUpload() async {
    _isCancelled = true;

    // Windowed (iOS) upload: cancel the native session and mark the row
    // cancelled — the watch in _awaitWindowedSession then resolves immediately.
    final windowedId = _activeWindowedSessionId;
    if (windowedId != null) {
      await IosWindowedUploaderService.instance.cancelSession(windowedId);
      await UploadSessionDb.instance.setSessionState(
        windowedId,
        SessionState.cancelled,
      );
    }

    // If no upload is in progress, complete immediately
    if (!_isUploading) {
      return;
    }

    // Create a completer to wait for cancellation to complete
    _cancelCompleter = Completer<void>();

    // Wait for cancellation with a timeout as safety net
    return _cancelCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        // If timeout, just complete and move on
        _cancelCompleter = null;
      },
    );
  }

  /// Called internally when cancellation handling is complete.
  void _completeCancellation() {
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
    _cancelCompleter = null;
  }

  /// Main entry point for uploading a file. Drives the [Upload] row through the
  /// Phase 2 windowed engine and awaits its terminal state, so the queue sees a
  /// single success/failure. [videoIndex]/[totalVideos] drive the "1/3 videos"
  /// notification copy. Returns [Failure] on error, or null on success.
  ///
  /// iOS-only: the windowed engine is the sole upload path (the legacy in-process
  /// chunk uploader and Android upload support were removed).
  Future<Failure?> uploadFile({
    required Upload upload,
    int videoIndex = 1,
    int totalVideos = 1,
  }) async {
    // Uploads run exclusively through the Phase 2 windowed engine (iOS). The
    // legacy in-process chunk uploader — and Android upload support — were
    // removed; the windowed engine is the only upload path.
    if (!Platform.isIOS) {
      UploadLog.add(
        "upload",
        "uploadFile called on non-iOS — unsupported (windowed engine is iOS-only)",
        level: UploadLogLevel.error,
      );
      return Failure(
        message: "Uploads are only supported on iOS.",
        code: ErrorType.unknown,
      );
    }
    return _uploadViaWindowedEngine(upload, videoIndex, totalVideos);
  }

  void _trackProgressMilestone(UploadProgress? progress) {
    if (progress == null) return;

    final upload = _analyticsCurrentUpload;
    if (upload == null || upload.id != progress.uploadId) return;

    const milestones = [25, 50, 75, 100];
    final reachedMilestones = _analyticsProgressMilestones.putIfAbsent(
      upload.id,
      () => <int>{},
    );

    for (final milestone in milestones) {
      if (progress.progress < milestone ||
          reachedMilestones.contains(milestone)) {
        continue;
      }
      reachedMilestones.add(milestone);
    }
  }

  Future<Failure?> _uploadViaWindowedEngine(
    Upload upload,
    int videoIndex,
    int totalVideos,
  ) async {
    _isUploading = true;
    _isCancelled = false;
    final startedAt = DateTime.now();

    // Analytics context — the _progressSubject listener emits milestones off this.
    _analyticsCurrentUpload = upload;
    _analyticsProgressMilestones.remove(upload.id);

    // Deterministic session id keyed on the legacy row, so a retry/resume
    // continues the *same* session (and reuses one created by the migrator)
    // instead of restarting from zero. startSession is idempotent.
    final sessionId = "legacy-${upload.id}";
    try {
      // SIZE-TRUTH GUARD — re-stat the source before a chunk plan can be
      // frozen off the row's snapshot. A row created while native
      // finalization was still writing the mcap carries a truncated size;
      // planning off it uploads a truncated prefix that "completes"
      // server-side but can never verify (and a zero size finalizes
      // vacuously, leaving nothing in R2 at all).
      final (verifiedSize, sizeErr) = await _verifySourceFile(upload);
      if (sizeErr != null) {
        UploadLog.add(
          "upload",
          "upload=${upload.id} source verification failed: ${sizeErr.message}",
          level: UploadLogLevel.error,
        );
        _trackWindowedTerminal(upload, sizeErr, videoIndex, totalVideos);
        return sizeErr;
      }

      if (await UploadSessionDb.instance.getSession(sessionId) == null) {
        await UploadSessionDb.instance.insertSession(
          UploadSessionsCompanion.insert(
            id: sessionId,
            filepath: upload.filepath,
            fileSize: verifiedSize,
            fileName: upload.fileName ?? "upload.mp4",
            mimeType: upload.mimeType ?? "video/mp4",
            durationMs: Value(upload.durationMs),
            thumbnailPath: Value(upload.thumnbnail),
            metadataFilepath: Value(upload.metadataFilepath),
            taskId: Value(upload.taskId),
            subtaskId: Value(upload.subtaskId),
          ),
        );
      }

      final startError = await WindowedUploadCoordinator.instance.startSession(
        sessionId,
      );
      if (startError != null) {
        // Couldn't start (e.g. register failed) — the session persists in a
        // non-terminal state so the queue's next retry resumes it.
        _trackWindowedTerminal(upload, startError, videoIndex, totalVideos);
        return startError;
      }

      await db.updateStatus(upload.id, UploadStatus.uploading);

      final result = await _awaitWindowedSession(
        sessionId,
        upload,
        videoIndex,
        totalVideos,
      );

      if (result == null) {
        // Mark the legacy Uploads row completed — parity with the legacy
        // complete path (complete_multipart_upload.dart). Without this the row
        // stays `pending`, the queue's DB watcher keeps re-seeding it, and the
        // queue re-runs the already-finished session in a loop.
        await db.updateStatus(upload.id, UploadStatus.completed);

        // Success — feed the speed/ETA estimator one whole-file sample.
        await UploadSpeedTracker.recordSample(
          fileSizeBytes: upload.filesize,
          elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        );
      }
      _trackWindowedTerminal(upload, result, videoIndex, totalVideos);
      return result;
    } finally {
      await _windowedWatchSub?.cancel();
      await _windowedProgressSub?.cancel();
      _windowedWatchSub = null;
      _windowedProgressSub = null;
      _activeWindowedSessionId = null;
      _isUploading = false;
      _progressSubject.add(null);
      _completeCancellation();
    }
  }

  /// Stats [upload]'s source file and returns its true on-disk size, healing
  /// the row's `filesize` column when the snapshot drifted. Fails when the
  /// file is missing/empty or is an mcap whose finalization never completed
  /// (no trailing magic) — uploading such a file produces a truncated object
  /// that "completes" but can never verify.
  Future<(int, Failure?)> _verifySourceFile(Upload upload) async {
    try {
      final resolvedPath = await ResolveFilePath.resolve(upload.filepath);
      final sourceFile = File(resolvedPath);
      if (!await sourceFile.exists()) {
        return (
          0,
          Failure(
            message: "Recording file not found on this device.",
            code: ErrorType.fileNotFound,
          ),
        );
      }

      final actualSize = await sourceFile.length();
      if (actualSize <= 0) {
        return (
          0,
          Failure(
            message: "Recording file on disk is empty.",
            code: ErrorType.uploadInComplete,
          ),
        );
      }

      final isMcap = resolvedPath.endsWith(".mcap");
      if (isMcap && !await McapFinalization.isFinalized(sourceFile)) {
        return (
          0,
          Failure(
            message:
                "Recording is still being finalized on disk (or was "
                "interrupted). If it just finished, retry in a few minutes.",
            code: ErrorType.uploadInComplete,
          ),
        );
      }

      if (upload.filesize != actualSize) {
        UploadLog.add(
          "upload",
          "upload=${upload.id} filesize drift row=${upload.filesize} "
              "actual=$actualSize — healing row before planning",
          level: UploadLogLevel.warn,
        );
        await db.updateFilesize(upload.id, actualSize);
      }
      return (actualSize, null);
    } catch (e) {
      return (0, Failure.fromException(e));
    }
  }

  /// Emits the terminal upload analytics event for the windowed path. A pause
  /// (`ErrorType.paused`) is not a terminal outcome, so it's skipped.
  void _trackWindowedTerminal(
    Upload upload,
    Failure? error,
    int videoIndex,
    int totalVideos,
  ) {
    if (error != null && error.code == ErrorType.paused) return;
  }

  /// Watches the windowed [UploadSession] until it reaches a terminal state,
  /// bridging **byte-level** progress into [_progressSubject] (keyed on the
  /// legacy `upload.id`, so the existing UI updates unchanged): completed-part
  /// bytes from the session-row watch + in-flight bytes per part from the
  /// native progress events.
  Future<Failure?> _awaitWindowedSession(
    String sessionId,
    Upload upload,
    int videoIndex,
    int totalVideos,
  ) {
    _activeWindowedSessionId = sessionId;
    final db = AppDatabase.instance;
    final completer = Completer<Failure?>();
    final fileSize = upload.filesize ?? 0;

    final inFlightBytes = <int, int>{};
    var completedBytes = 0;
    var uploadedParts = 0;
    var totalParts = 0;

    // Monotonic high-water (fraction 0..1). Seeded from the durable
    // `upload.progress` so a cold relaunch resumes from the last value the user
    // saw instead of dropping: the in-flight window (held only in-memory) is
    // lost across a force-quit and its parts re-upload, but the bar must not
    // visibly go backward. `_lastPersisted` throttles the durable write.
    var maxProgress = (upload.progress ?? 0).toDouble().clamp(0.0, 1.0);
    var lastPersisted = maxProgress;

    void emitProgress() {
      if (fileSize <= 0) return;
      final inFlight = inFlightBytes.values.fold<int>(0, (sum, b) => sum + b);
      final bytes = (completedBytes + inFlight).clamp(0, fileSize);
      final fraction = (bytes / fileSize).clamp(0.0, 1.0);
      if (fraction > maxProgress) maxProgress = fraction;
      // Persist the high-water to the durable Uploads row (throttled to ≥1%) so
      // the tile's `upload.progress` fallback renders it on the next cold start.
      if (maxProgress - lastPersisted >= 0.01) {
        lastPersisted = maxProgress;
        unawaited(UploadDb.instance.updateProgress(upload.id, maxProgress));
      }
      _progressSubject.add((
        uploadId: upload.id,
        current: uploadedParts,
        total: totalParts,
        progress: (maxProgress * 100).round().clamp(0, 100),
        videoIndex: videoIndex,
        totalVideos: totalVideos,
      ));
    }

    // Byte-level progress (and remove finished parts from the in-flight sum).
    _windowedProgressSub = IosWindowedUploaderService.instance.events().listen((
      event,
    ) {
      if (event.sessionId != sessionId) return;
      switch (event) {
        case WindowedProgress(:final partNumber, :final bytesSent):
          inFlightBytes[partNumber] = bytesSent;
          emitProgress();
        case WindowedPartCompleted(:final partNumber):
          inFlightBytes.remove(partNumber);
        case WindowedPartFailed(:final partNumber):
          inFlightBytes.remove(partNumber);
        default:
          break;
      }
    });

    final query = db.select(db.uploadSessions)
      ..where((s) => s.id.equals(sessionId));

    _windowedWatchSub = query.watchSingleOrNull().listen((session) async {
      if (completer.isCompleted) return;

      // Cancel requested, or the session row was deleted out from under us
      // (e.g. the user removed this upload via the tile X, which deletes the
      // session + part rows). Either way resolve as cancelled: if we returned
      // early on a null row instead, the completer would never fire and
      // _processNext would hang with _isProcessing stuck true, wedging every
      // later upload at 0% ("already_processing").
      if (_isCancelled || session == null) {
        await IosWindowedUploaderService.instance.cancelSession(sessionId);
        completer.complete(
          Failure(message: "Upload cancelled", code: ErrorType.cancelled),
        );
        return;
      }

      if (_isPaused) {
        // Queue-level pause: let in-flight tasks finish, stop refilling, park
        // the session so the next resume continues it (ErrorType.paused tells
        // the queue to keep this row parked, not failed).
        await IosWindowedUploaderService.instance.pauseSession(sessionId);
        await UploadSessionDb.instance.setSessionState(
          sessionId,
          SessionState.paused,
        );
        if (!completer.isCompleted) {
          completer.complete(
            Failure(message: "Upload paused", code: ErrorType.paused),
          );
        }
        return;
      }

      // Refresh the completed-part baseline (the session row ticks per part).
      final counts = await UploadSessionDb.instance.partCounts(sessionId);
      uploadedParts = counts.uploaded;
      totalParts = counts.total == 0 ? (session.partCount ?? 0) : counts.total;
      completedBytes = await UploadSessionDb.instance.uploadedBytes(sessionId);
      emitProgress();

      switch (session.state) {
        case SessionState.completed:
          completer.complete(null);
        case SessionState.failedTerminal:
          completer.complete(
            Failure(
              message:
                  session.lastErrorDetail ??
                  session.lastErrorCode ??
                  "Upload failed",
              code: ErrorType.unknown,
            ),
          );
        case SessionState.cancelled:
          completer.complete(
            Failure(message: "Upload cancelled", code: ErrorType.cancelled),
          );
        case SessionState.paused:
          completer.complete(
            Failure(message: "Upload paused", code: ErrorType.paused),
          );
        default:
          break; // non-terminal — keep waiting
      }
    });

    return completer.future;
  }
}
