import "dart:async";
import "dart:io";

import "package:stera/src/modules/upload/providers/managers/upload_progress_manager.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/connectivity_service/connectivity_service.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/legacy_upload_migration_service/legacy_upload_migration_service.dart";
import "package:stera/src/services/foreground_notification_service/foreground_notification_service.dart";
import "package:stera/src/services/upload_service/channels/upload_foreground_notifier.dart";
import "package:stera/src/services/upload_service/data/repo/upload_repo.dart";
import "package:stera/src/services/upload_service/diagnostics/upload_log.dart";
import "package:stera/src/services/upload_service/uploads_service.dart";
import "package:stera/src/services/upload_service/utils/resolve_file_path.dart";
import "package:flutter/foundation.dart";
import "package:path/path.dart" as p;

class UploadQueueManager extends ChangeNotifier {
  UploadQueueManager._internal();

  static final UploadQueueManager _instance = UploadQueueManager._internal();
  static UploadQueueManager get instance => _instance;

  final UploadDb _db = UploadDb.instance;
  final UploadsService _uploadService = UploadsService.instance;

  StreamSubscription<List<Upload>>? _dbSubscription;
  StreamSubscription<bool>? connectivitySubscription;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  bool _willProcess =
      false; // set when we're about to call _processNext() to prevent races

  bool _isWatching = false;
  bool get isWatching => _isWatching;

  bool _isCancelling = false;
  bool get isCancelling => _isCancelling;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// Throttling for database update notifications
  DateTime? _lastDbNotifyTime;
  static const Duration _dbNotifyThrottle = Duration(milliseconds: 500);
  Timer? _pendingDbNotifyTimer;

  /// Upload ids whose most recent failure was a transient network/timeout
  /// error. These are eligible for automatic recovery — a backoff re-attempt
  /// while in-session, and a fresh attempt when connectivity is restored.
  /// Cleared on success, manual retry, or cancel.
  final Set<int> _networkFailedUploadIds = {};

  /// Per-upload backoff: the queue skips a transiently-failed (still resumable)
  /// row until this time so re-attempts are spaced instead of hammering the
  /// network in a tight loop.
  final Map<int, DateTime> _cooldownUntil = {};

  /// Uploads the user paused individually. Guards the processing loop against
  /// picking a row whose paused status hasn't landed in the DB watcher yet.
  final Set<int> _pausedUploadIds = {};

  /// Set while a single-upload pause of the in-flight upload is awaiting the
  /// service to stop after its current chunk batch. Distinguishes a per-upload
  /// pause from the queue-level pause when uploadFile returns ErrorType.paused.
  int? _pauseRequestedForUploadId;

  /// Wakes the queue when the soonest cooldown expires.
  Timer? _cooldownTimer;

  Upload? _currentUpload;
  Upload? get currentUpload => _currentUpload;

  List<Upload> _pendingQueue = [];
  List<Upload> get pendingQueue => List.unmodifiable(_pendingQueue);

  final List<Failure> _errors = [];
  List<Failure> get errors => List.unmodifiable(_errors);

  final Set<int> _batchUploadIds = {};
  Set<int> get batchUploadIds => Set.unmodifiable(_batchUploadIds);

  int _batchTotalCount = 0;
  int get batchTotalCount => _batchTotalCount;

  int _batchCompletedCount = 0;
  int get batchCompletedCount => _batchCompletedCount;
  List<Upload> _successfulUploads = [];
  List<Upload> get successfulUploads => _successfulUploads;
  set successfulUploads(List<Upload> value) {
    _successfulUploads = value;
    notifyListeners();
  }

  void Function(List<Upload> completedUploads)? onBatchComplete;

  void Function(Upload upload, Failure error)? onUploadFailed;

  void Function(Upload upload)? onUploadComplete;

  Failure? processQueue({List<Upload>? newUploads}) {
    debugPrint("📋 UploadQueueManager: processQueue called");

    final seededUploads = newUploads != null && newUploads.isNotEmpty
        ? newUploads
        : null;

    if (seededUploads != null) {
      _batchUploadIds.addAll(seededUploads.map((u) => u.id));
      debugPrint(
        "📋 UploadQueueManager: Added ${seededUploads.length} uploads to batch",
      );
      _startWatching();
      _mergePendingQueueFromSeed(seededUploads);
      if (_pendingQueue.isEmpty) {
        debugPrint(
          "⚠️ UploadQueueManager: processQueue — no pending/uploading rows "
          "after seed merge; cannot start",
        );
        return Failure(
          code: ErrorType.validation,
          message:
              "Could not start uploads. Please try selecting your videos again.",
        );
      }
    } else if (_pendingQueue.isNotEmpty) {
      // e.g. resume() after pause() stopped the DB subscription
      _startWatching();
    }

    if (_isProcessing || _willProcess) {
      // This is expected when _processNext() is already running (async race)
      // Only log as warning if NOT because we will process soon (genuine busy)
      final cause = _willProcess ? "will_process" : "already_processing";
      if (seededUploads != null) {
      }
      debugPrint(
        "📋 UploadQueueManager: Skipped - $cause (${_pendingQueue.length} pending, watching=$_isWatching)",
      );
      notifyListeners();
      return null;
    }

    if (_pendingQueue.isEmpty) {
      return null;
    }

    if (!_isPaused) {
      debugPrint(
        "📋 UploadQueueManager: Kicking _processNext (${_pendingQueue.length} pending)",
      );
      _willProcess = true;
      _processNext();
    }

    notifyListeners();
    return null;
  }

  /// Merges [seed] rows that are pending/uploading into [_pendingQueue] so
  /// processing can start before the next DB watch emission.
  void _mergePendingQueueFromSeed(List<Upload> seed) {
    final seeds = seed
        .where(
          (u) =>
              u.status == UploadStatus.pending ||
              u.status == UploadStatus.uploading,
        )
        .toList();
    if (seeds.isEmpty) return;

    final byId = <int, Upload>{for (final u in _pendingQueue) u.id: u};
    for (final u in seeds) {
      byId[u.id] = u;
    }
    final merged = byId.values.toList();
    merged.sort((a, b) {
      final progressA = a.progress ?? 0;
      final progressB = b.progress ?? 0;
      return progressB.compareTo(progressA);
    });
    _pendingQueue = merged;
  }

  /// Pauses the upload queue after the current chunk batch completes.
  /// Does not change any upload status - simply stops processing new uploads.
  Future<void> pauseQueue() async {
    if (_isPaused) return;

    debugPrint("⏸️ UploadQueueManager: Pausing queue");
    _isPaused = true;

    // Signal the upload service to pause after current chunks complete
    _uploadService.requestPause();

    // Update notification to show paused state
    await UploadForegroundNotifier.updatePausedState(isPaused: true);

    notifyListeners();
  }

  /// Resumes the upload queue and continues processing.
  Future<void> resumeQueue() async {
    if (!_isPaused) return;

    debugPrint("▶️ UploadQueueManager: Resuming queue");
    _isPaused = false;

    // Clear the pause flag in upload service
    _uploadService.clearPause();

    // Update notification to show active state
    await UploadForegroundNotifier.updatePausedState(isPaused: false);

    notifyListeners();

    // Continue processing if we have pending uploads and aren't already processing
    if (_pendingQueue.isNotEmpty && !_isProcessing) {
      _willProcess = true;
      _processNext();
    }
  }

  /// Clears the paused state without resuming processing.
  /// Used when resuming uploads on app start to ensure clean state.
  void clearPauseState() {
    _isPaused = false;
    _uploadService.clearPause();
  }

  /// Pauses a single upload without affecting the rest of the queue.
  ///
  /// If [id] is the upload currently in flight, the service is signalled to
  /// stop after its current chunk batch; the row is parked as
  /// [UploadStatus.paused] in [_processNext] and the queue moves on to the
  /// next upload. A queued row is parked immediately. Multipart state and
  /// progress are preserved so resuming continues from where it left off.
  Future<void> pauseUpload(int id) async {
    final row = await _db.getById(id);
    if (row == null ||
        (row.status != UploadStatus.pending &&
            row.status != UploadStatus.uploading)) {
      return;
    }

    debugPrint("⏸️ UploadQueueManager: Pausing upload $id");
    _pausedUploadIds.add(id);
    _networkFailedUploadIds.remove(id);
    _cooldownUntil.remove(id);


    if (_currentUpload?.id == id && _isProcessing) {
      // In flight: stop after the in-flight chunks drain; _processNext
      // finalizes the park when the service returns ErrorType.paused.
      _pauseRequestedForUploadId = id;
      _uploadService.requestPause();
      // Park in the DB immediately so the UI flips to paused right away.
      // Chunk flushes only write progress/parts columns, so this survives
      // the drain.
      await _db.updateStatus(id, UploadStatus.paused);
    } else {
      await _db.update(id, row.copyWith(status: UploadStatus.paused));
      _pendingQueue = _pendingQueue.where((u) => u.id != id).toList();
      _batchUploadIds.remove(id);
      if (_batchTotalCount > 0) _batchTotalCount -= 1;
    }

    notifyListeners();
  }

  /// Resumes an individually paused upload, preserving its multipart state so
  /// it continues from where it left off.
  Future<void> resumeUpload(int id) async {
    final row = await _db.getById(id);
    if (row == null || row.status != UploadStatus.paused) return;

    debugPrint("▶️ UploadQueueManager: Resuming upload $id");
    _pausedUploadIds.remove(id);

    // Resumed before the in-flight pause landed (chunks still draining):
    // withdraw the request so the service just keeps going.
    if (_pauseRequestedForUploadId == id) {
      _pauseRequestedForUploadId = null;
      if (!_isPaused) _uploadService.clearPause();
    }


    await _db.update(id, row.copyWith(status: UploadStatus.pending));
    final updated = await _db.getById(id);
    if (updated != null) {
      processQueue(newUploads: [updated]);
    }
  }

  void pause() {
    debugPrint("📋 UploadQueueManager: Pausing");
    _stopWatching();
  }

  void resume() {
    debugPrint("📋 UploadQueueManager: Resuming");
    processQueue();
  }

  /// Stops an individual upload and resets its DB row to [UploadStatus.notStarted]
  /// so the local video remains on device and can be uploaded again later.
  /// Does not delete local files.
  Future<void> cancelUpload(int id) async {
    final row = await _db.getById(id);
    if (row == null ||
        row.status == UploadStatus.notStarted ||
        row.status == UploadStatus.completed) {
      return;
    }

    debugPrint(
      "📋 UploadQueueManager: Cancelling upload $id (reset to notStarted)",
    );

    final wasInFlight = _currentUpload?.id == id && _isProcessing;
    _removeUploadFromQueueState(id);

    if (wasInFlight) {
      await _uploadService.cancelCurrentUpload();
    }
    await _abortMultipartIfExists(row);
    await _uploadService.cancelWindowedSessionFor(id);

    if (wasInFlight) {
      _uploadService.clearProgress();
    }

    await _db.resetToNotStarted(id);
    notifyListeners();
  }

  /// Permanently removes an upload from the queue and deletes its local files.
  Future<void> deleteUpload(Upload upload) async {
    if (upload.status == UploadStatus.completed) return;

    debugPrint("📋 UploadQueueManager: Deleting upload ${upload.id}");

    final wasInFlight = _currentUpload?.id == upload.id && _isProcessing;
    _removeUploadFromQueueState(upload.id);

    if (wasInFlight) {
      await _uploadService.cancelCurrentUpload();
    }
    await _abortMultipartIfExists(upload);
    await _uploadService.cancelWindowedSessionFor(upload.id);

    if (wasInFlight) {
      _uploadService.clearProgress();
    }

    await _deleteRecordingDirectory(upload);
    await _db.delete(upload.id);
    notifyListeners();
  }

  Future<void> cancelCurrent() async {
    if (_currentUpload == null) return;
    debugPrint(
      "📋 UploadQueueManager: Cancelling current upload ${_currentUpload!.id}",
    );
    await _db.cancel(_currentUpload!);
  }

  Future<void> cancelAll() async {
    debugPrint(
      "📋 UploadQueueManager: Cancelling all ${_pendingQueue.length} uploads",
    );

    _isCancelling = true;
    notifyListeners();

    try {
      // Clear paused state if we were paused
      if (_isPaused) {
        _isPaused = false;
        _uploadService.clearPause();
      }

      // Clear the progress stream to update UI immediately
      _uploadService.clearProgress();

      final activeIds = await _collectActiveUploadIds();

      // Cancel current upload and wait for it to finish processing
      // This ensures all chunks are properly stopped before we continue.
      await _uploadService.cancelCurrentUpload();

      for (final id in activeIds) {
        final row = await _db.getById(id);
        if (row == null) continue;
        await _abortMultipartIfExists(row);
        await _uploadService.cancelWindowedSessionFor(id);
        _deleteRecordingFiles(row);
        await _db.delete(id);
      }

      _currentUpload = null;
      _pendingQueue = [];
      _pausedUploadIds.clear();
      _pauseRequestedForUploadId = null;

      // Stop the foreground notification service
      UploadForegroundNotifier.removeUploadCancelListener();
      UploadForegroundNotifier.removeUploadPauseListener();
      UploadForegroundNotifier.removeUploadResumeListener();
      await UploadForegroundNotifier.stopService();

      // Clear batch tracking state
      _batchUploadIds.clear();
      _batchTotalCount = 0;
      _batchCompletedCount = 0;
      successfulUploads.clear();
      _errors.clear();
      _networkFailedUploadIds.clear();
      _cooldownUntil.clear();
      _cooldownTimer?.cancel();
      _cooldownTimer = null;

      // Stop watching the database to prevent new uploads from starting
      _stopWatching();
    } finally {
      // No more arbitrary delay - cancellation is confirmed complete
      _isCancelling = false;
      notifyListeners();
    }
  }

  /// Cancels every active/queued/paused upload and resets them to
  /// [UploadStatus.notStarted], keeping the local recordings — the bulk
  /// equivalent of the per-upload [cancelUpload]. (Use [cancelAll] to also
  /// delete the local files.)
  Future<void> cancelAllToNotStarted() async {
    _isCancelling = true;
    notifyListeners();

    try {
      // Freeze the processor so it can't promote a queued upload to in-flight
      // while we're resetting (re-established on the next submit/processQueue).
      _stopWatching();
      if (_isPaused) {
        _isPaused = false;
        _uploadService.clearPause();
      }

      // Snapshot every non-terminal upload id up front, since cancelUpload
      // mutates the in-memory queue as it goes.
      final ids = await _collectActiveUploadIds();

      // Reuse the per-upload teardown (cancels in-flight chunks, aborts
      // multipart, tears down the windowed session, resets to notStarted).
      for (final id in ids) {
        await cancelUpload(id);
      }

      // Nothing is uploading anymore — stop the foreground notification.
      UploadForegroundNotifier.removeUploadCancelListener();
      UploadForegroundNotifier.removeUploadPauseListener();
      UploadForegroundNotifier.removeUploadResumeListener();
      await UploadForegroundNotifier.stopService();
    } finally {
      _isCancelling = false;
      notifyListeners();
    }
  }

  /// Retries a single failed upload, preserving the multipart upload and the
  /// parts already on S3 so the retry resumes from where it left off instead
  /// of restarting at 0%. Presigned URLs are cleared (refetched fresh) and
  /// the retry budget is reset.
  Future<void> retry(Upload upload) async {
    debugPrint("📋 UploadQueueManager: Retrying upload ${upload.id}");
    // Manual retry takes over recovery for this row.
    _networkFailedUploadIds.remove(upload.id);
    _cooldownUntil.remove(upload.id);

    // Re-arm the windowed session FIRST — otherwise it stays `failedTerminal`
    // and startSession short-circuits to an instant failure (retry loop).
    await UploadSessionDb.instance.resetForRetry("legacy-${upload.id}");

    // Keep the multipart upload and completed parts; refresh status/budget/URLs
    final reset = await _db.prepareForRetry(upload.id);

    if (reset != null) {
      processQueue(newUploads: [reset]);
    }
  }

  /// Retries all failed uploads, preserving multipart progress (see [retry]).
  Future<void> retryAllFailed() async {
    // Manual retry takes over recovery for all failed rows.
    _networkFailedUploadIds.clear();
    _cooldownUntil.clear();
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    final failed = await _db.getByStatus(UploadStatus.failed);
    debugPrint(
      "📋 UploadQueueManager: Retrying ${failed.length} failed uploads",
    );

    final resetUploads = <Upload>[];
    for (final upload in failed) {
      // Re-arm the windowed session first (see [retry]) so startSession
      // resumes instead of instantly re-failing on its `failedTerminal` guard.
      await UploadSessionDb.instance.resetForRetry("legacy-${upload.id}");
      final reset = await _db.prepareForRetry(upload.id);
      if (reset != null) resetUploads.add(reset);
    }

    if (resetUploads.isNotEmpty) {
      processQueue(newUploads: resetUploads);
    }
  }

  /// Cancels every failed upload: each is reset to [UploadStatus.notStarted]
  /// (local files kept), so they leave the Failed section but can be uploaded
  /// again later. The bulk sibling of the per-tile "Cancel upload".
  Future<void> cancelAllFailed() async {
    final failed = await _db.getByStatus(UploadStatus.failed);
    debugPrint("📋 UploadQueueManager: Cancelling ${failed.length} failed uploads");
    for (final upload in failed) {
      await cancelUpload(upload.id);
    }
  }

  /// Permanently removes every failed upload and deletes its local files. The
  /// bulk sibling of the per-tile "Delete".
  Future<void> deleteAllFailed() async {
    final failed = await _db.getByStatus(UploadStatus.failed);
    debugPrint("📋 UploadQueueManager: Deleting ${failed.length} failed uploads");
    for (final upload in failed) {
      await deleteUpload(upload);
    }
  }

  int get queueLength => _pendingQueue.length;
  bool get hasPendingUploads => _pendingQueue.isNotEmpty;

  void _startWatching() {
    if (_isWatching) return;

    _isWatching = true;
    debugPrint("📋 UploadQueueManager: Started watching DB");
    _dbSubscription = _db.watch().listen(_onDatabaseUpdate);

    // Subscribe to connectivity changes for auto-pause/resume
    connectivitySubscription = ConnectivityService.instance.connectivityStream
        .listen(_onConnectivityChanged);

    // Set up pause/resume listeners for notification actions
    UploadForegroundNotifier.setUploadPauseListener(() {
      pauseQueue();
    });
    UploadForegroundNotifier.setUploadResumeListener(() {
      resumeQueue();
    });

    notifyListeners();
  }

  void _onConnectivityChanged(bool isOnline) {
    if (isOnline) {
      debugPrint("📋 UploadQueueManager: Back online, resuming uploads");
      // Connectivity is back — drop any backoff cooldowns immediately and
      // grant network-failed uploads a fresh attempt (progress is preserved).
      _cooldownUntil.clear();
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
      unawaited(_resumeNetworkFailedUploads());
      if (_pendingQueue.isNotEmpty && !_isProcessing) {
        _willProcess = true;
        _processNext();
      }
    } else {
      debugPrint("📋 UploadQueueManager: Offline, uploads will wait");
    }
  }

  /// Resumes uploads that failed terminally due to a network/timeout error.
  ///
  /// Called when connectivity is restored. Unlike the manual retry path
  /// ([retry]/[retryAllFailed]), this preserves the multipart state so the
  /// upload resumes from where it left off rather than restarting at 0%, and
  /// resets the retry budget since the failures were caused by being offline.
  Future<void> _resumeNetworkFailedUploads() async {
    if (_networkFailedUploadIds.isEmpty) return;

    final ids = _networkFailedUploadIds.toList();
    var resumedAny = false;
    for (final id in ids) {
      final row = await _db.getById(id);
      if (row == null) {
        _networkFailedUploadIds.remove(id);
        continue;
      }
      // Still pending/uploading (e.g. cooling down): nothing to flip — it will
      // be picked up now that cooldowns are cleared.
      if (row.status != UploadStatus.failed) continue;

      await _db.update(
        id,
        row.copyWith(status: UploadStatus.pending, retryCount: 0),
      );
      resumedAny = true;
      debugPrint(
        "🔁 UploadQueueManager: Resuming network-failed upload $id on reconnect",
      );
    }

    if (resumedAny) {
      _startWatching();
      processQueue();
    }
  }

  /// Exponential backoff before re-attempting a transiently-failed upload.
  /// [retryCount] is the upload's retry count after the failure (>= 1):
  /// 1 → 4s, 2 → 8s, capped at 30s.
  void _registerCooldown(int id, int retryCount) {
    final base = 1 << (retryCount + 1);
    final seconds = base > 30 ? 30 : base;
    _cooldownUntil[id] = DateTime.now().add(Duration(seconds: seconds));
    _scheduleCooldownWake();
  }

  bool _isCoolingDown(int id, DateTime now) {
    final until = _cooldownUntil[id];
    if (until == null) return false;
    if (now.isBefore(until)) return true;
    _cooldownUntil.remove(id);
    return false;
  }

  /// Schedules a single timer to re-kick processing when the soonest active
  /// cooldown elapses.
  void _scheduleCooldownWake() {
    if (_cooldownUntil.isEmpty) return;
    final now = DateTime.now();
    DateTime? soonest;
    for (final until in _cooldownUntil.values) {
      if (until.isAfter(now) && (soonest == null || until.isBefore(soonest))) {
        soonest = until;
      }
    }
    if (soonest == null) return;

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(
      soonest.difference(now) + const Duration(milliseconds: 250),
      () {
        _cooldownTimer = null;
        if (!_isProcessing &&
            !_isPaused &&
            _isWatching &&
            _pendingQueue.isNotEmpty) {
          _willProcess = true;
          _processNext();
        }
      },
    );
  }

  void _stopWatching() {
    if (!_isWatching) return;

    _isWatching = false;
    _dbSubscription?.cancel();
    _dbSubscription = null;
    connectivitySubscription?.cancel();
    connectivitySubscription = null;

    // Remove pause/resume listeners
    UploadForegroundNotifier.removeUploadPauseListener();
    UploadForegroundNotifier.removeUploadResumeListener();

    debugPrint("📋 UploadQueueManager: Stopped watching DB");
    notifyListeners();
  }

  void _onDatabaseUpdate(List<Upload> uploads) {
    final oldLength = _pendingQueue.length;

    final pending = uploads
        .where(
          (u) =>
              u.status == UploadStatus.pending ||
              u.status == UploadStatus.uploading,
        )
        .toList();

    pending.sort((a, b) {
      final progressA = a.progress ?? 0;
      final progressB = b.progress ?? 0;
      return progressB.compareTo(progressA);
    });

    _pendingQueue = pending;

    debugPrint(
      "📋 UploadQueueManager: Queue updated - ${_pendingQueue.length} pending "
      "(${_pendingQueue.where((u) => (u.progress ?? 0) > 0).length} with progress)",
    );

    if (!_isProcessing && _pendingQueue.isNotEmpty) {
      _willProcess = true;
      _processNext();
    }

    // Throttle notifications to reduce UI overhead during uploads
    // Always notify immediately if queue length changed (important state change)
    if (oldLength != _pendingQueue.length) {
      _notifyListenersThrottled(forceImmediate: true);
    } else {
      _notifyListenersThrottled();
    }
  }

  /// Throttled notification to reduce main thread overhead during uploads.
  /// Important events can force immediate notification.
  void _notifyListenersThrottled({bool forceImmediate = false}) {
    final now = DateTime.now();

    // Always notify immediately for important events
    if (forceImmediate) {
      _pendingDbNotifyTimer?.cancel();
      _lastDbNotifyTime = now;
      notifyListeners();
      return;
    }

    // Check if enough time has passed since last notification
    if (_lastDbNotifyTime == null ||
        now.difference(_lastDbNotifyTime!) >= _dbNotifyThrottle) {
      _pendingDbNotifyTimer?.cancel();
      _lastDbNotifyTime = now;
      notifyListeners();
    } else {
      // Schedule a delayed notification if one isn't already pending
      _pendingDbNotifyTimer?.cancel();
      final remaining = _dbNotifyThrottle - now.difference(_lastDbNotifyTime!);
      _pendingDbNotifyTimer = Timer(remaining, () {
        _lastDbNotifyTime = DateTime.now();
        notifyListeners();
      });
    }
  }

  Future<void> _processNext() async {
    if (_isProcessing || !_isWatching) {
      _willProcess = false;
      return;
    }

    if (_pendingQueue.isEmpty) {
      _willProcess = false;
      return;
    }

    _willProcess = false;
    _isProcessing = true;

    _batchTotalCount = _pendingQueue.length;
    _batchCompletedCount = 0;
    successfulUploads.clear();

    debugPrint(
      "📋 UploadQueueManager: Starting batch of $_batchTotalCount uploads",
    );

    notifyListeners();

    while (_pendingQueue.isNotEmpty && _isWatching && !_isPaused) {
      // Pick the first row that isn't in a backoff cooldown. If everything
      // left is cooling down, stop and let the cooldown timer re-kick us.
      final now = DateTime.now();
      Upload? upload;
      for (final u in _pendingQueue) {
        // Skip rows paused individually — the DB watcher may not have
        // dropped them from the queue yet.
        if (_pausedUploadIds.contains(u.id)) continue;
        if (!_isCoolingDown(u.id, now)) {
          upload = u;
          break;
        }
      }
      if (upload == null) {
        debugPrint(
          "⏳ UploadQueueManager: All pending uploads cooling down; waiting",
        );
        _scheduleCooldownWake();
        break;
      }

      _currentUpload = upload;

      // Set file size for dynamic throttling (larger files = fewer UI updates)
      UploadProgressManager.instance.setCurrentFileSize(upload.filesize);

      final videoIndex = _batchCompletedCount + 1;
      final totalVideos = _batchTotalCount;

      debugPrint(
        "📋 UploadQueueManager: Processing ${upload.id} "
        "($videoIndex/$totalVideos, progress: ${upload.progress ?? 0}%)",
      );
      UploadLog.add(
        "queue",
        "processing upload=${upload.id} ($videoIndex/$totalVideos) "
            "size=${upload.filesize} progress=${upload.progress ?? 0}",
      );

      notifyListeners();

      final error = await _uploadService.uploadFile(
        upload: upload,
        videoIndex: videoIndex,
        totalVideos: totalVideos,
      );

      // A per-upload pause that never hit a checkpoint (the upload finished,
      // failed or was cancelled first) must not spill onto the next upload or
      // leave this row stuck in the skip set.
      if (_pauseRequestedForUploadId == upload.id &&
          error?.code != ErrorType.paused) {
        _pauseRequestedForUploadId = null;
        _pausedUploadIds.remove(upload.id);
        if (!_isPaused) _uploadService.clearPause();
      }

      if (error != null) {
        // Check if this was a pause - don't treat it as a failure
        if (error.code == ErrorType.paused) {
          final singlePauseId = _pauseRequestedForUploadId;
          _pauseRequestedForUploadId = null;

          if (!_isPaused && singlePauseId != null) {
            // Per-upload pause: park this row as paused and keep the queue
            // moving. Progress and multipart state stay in the DB so resuming
            // continues from where it left off.
            _uploadService.clearPause();
            if (singlePauseId == upload.id &&
                _pausedUploadIds.contains(upload.id)) {
              final pausedId = upload.id;
              await _db.updateStatus(pausedId, UploadStatus.paused);
              _pendingQueue = _pendingQueue
                  .where((u) => u.id != pausedId)
                  .toList();
              _batchUploadIds.remove(pausedId);
              if (_batchTotalCount > 0) _batchTotalCount -= 1;
              // Drop the stale progress card for the parked upload.
              _uploadService.clearProgress();
              debugPrint(
                "⏸️ UploadQueueManager: Upload ${upload.id} paused individually",
              );
            } else {
              // Either the pause was withdrawn (resumed mid-drain) or it was
              // requested for an upload that already finished and spilled
              // onto this one. Leave this row resumable in the queue.
              _pausedUploadIds.remove(singlePauseId);
            }
            _currentUpload = null;
            notifyListeners();
            continue;
          }

          debugPrint("⏸️ UploadQueueManager: Upload ${upload.id} paused");
          // Don't increment batch count or add to errors - the upload is still in progress
          _currentUpload = null;
          notifyListeners();
          break; // Exit the loop since we're paused
        }

        // Transient network/timeout failure with retry budget left: the upload
        // service kept the row resumable (status pending/uploading). Schedule a
        // backoff and re-attempt silently instead of surfacing a failure — the
        // upload resumes from where it left off.
        if (error.code == ErrorType.network) {
          final freshRow = await _db.getById(upload.id);
          final keptResumable =
              freshRow != null &&
              (freshRow.status == UploadStatus.pending ||
                  freshRow.status == UploadStatus.uploading);
          // Remember it either way so a reconnect can recover it even if it
          // later exhausts retries.
          _networkFailedUploadIds.add(upload.id);
          if (keptResumable && _isWatching) {
            _registerCooldown(upload.id, freshRow.retryCount);
            debugPrint(
              "🔁 UploadQueueManager: Upload ${upload.id} transient failure; "
              "auto-retry scheduled (attempt ${freshRow.retryCount})",
            );
            _currentUpload = null;
            notifyListeners();
            // Don't count as completed — re-evaluate the queue (the cooling-down
            // row will be skipped until its backoff elapses).
            continue;
          }
        }

        debugPrint(
          "❌ UploadQueueManager: Upload ${upload.id} failed: ${error.message}",
        );
        UploadLog.add(
          "queue",
          "upload=${upload.id} FAILED code=${error.code.name} msg=${error.message}",
          level: UploadLogLevel.error,
        );
        if (error.code != ErrorType.cancelled &&
            error.code != ErrorType.paused) {
          final row = await _db.getById(upload.id);
          if (row != null && row.status != UploadStatus.completed) {
            await _db.updateStatus(upload.id, UploadStatus.failed);
          }
        }
        _errors.add(error);

        // Clear progress so the progress card disappears on failure
        UploadProgressManager.instance.reset();

        onUploadFailed?.call(upload, error);
      } else {
        debugPrint("✅ UploadQueueManager: Upload ${upload.id} completed");
        UploadLog.add("queue", "upload=${upload.id} COMPLETED");
        successfulUploads.add(upload);
        _networkFailedUploadIds.remove(upload.id);
        _cooldownUntil.remove(upload.id);
        onUploadComplete?.call(upload);
      }

      _batchCompletedCount++;

      _currentUpload = null;
      notifyListeners();

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    _isProcessing = false;

    // Only call _onQueueEmpty if we're not paused (paused means we intentionally stopped)
    if (!_isPaused) {
      _onQueueEmpty();
    } else {
      debugPrint(
        "⏸️ UploadQueueManager: Queue paused, not calling onQueueEmpty",
      );
    }
    notifyListeners();
  }

  Future<void> _onQueueEmpty() async {
    debugPrint("📋 UploadQueueManager: Queue empty");

    if (_batchUploadIds.isEmpty) {
      _errors.clear();
      return;
    }

    await _checkBatchCompletion();
    _errors.clear();
  }

  Future<void> _checkBatchCompletion() async {
    if (_batchCompletedCount < _batchTotalCount && _batchTotalCount > 0) {
      debugPrint(
        "📋 UploadQueueManager: Batch not complete yet ($_batchCompletedCount/$_batchTotalCount)",
      );
      return;
    }

    final List<Upload> remainingUploads = [];

    for (final id in _batchUploadIds) {
      final upload = await _db.getById(id);
      if (upload != null) {
        remainingUploads.add(upload);
      }
    }

    final hasFailures = remainingUploads.any(
      (u) =>
          u.status == UploadStatus.cancelled || u.status == UploadStatus.failed,
    );

    if (successfulUploads.isNotEmpty && !hasFailures) {
      debugPrint("📋 UploadQueueManager: Batch completed successfully!");

      await ForegroundNotificationService.showNotification(
        title: "Congratulations!",
        body:
            "${successfulUploads.length} ${successfulUploads.length == 1 ? 'video' : 'videos'} uploaded successfully",
      );

      onBatchComplete?.call(successfulUploads);
    } else if (hasFailures) {
      debugPrint(
        "📋 UploadQueueManager: Batch finished with ${_errors.length} errors",
      );
    }

    _batchUploadIds.clear();
    _batchTotalCount = 0;
    _batchCompletedCount = 0;
    notifyListeners();
  }

  /// Every non-terminal upload the queue may still own — in-memory plus DB so
  /// cancel paths don't miss rows that fell out of sync with [_pendingQueue].
  Future<Set<int>> _collectActiveUploadIds() async {
    final ids = <int>{
      if (_currentUpload != null) _currentUpload!.id,
      ..._pendingQueue.map((u) => u.id),
    };
    for (final status in const [
      UploadStatus.uploading,
      UploadStatus.pending,
      UploadStatus.paused,
    ]) {
      final rows = await _db.getByStatus(status);
      ids.addAll(rows.map((u) => u.id));
    }
    return ids;
  }

  /// Aborts the server-side multipart upload for [upload] when one exists.
  ///
  /// Windowed uploads persist identity on [UploadSession] (`s3Key` /
  /// `s3UploadId`); legacy rows may only have [Upload.multipartStartResponse].
  Future<void> _abortMultipartIfExists(Upload upload) async {
    final row = await _db.getById(upload.id) ?? upload;
    final session = await UploadSessionDb.instance.getSession(
      LegacyUploadMigrator.sessionIdFor(row),
    );

    final key = session?.s3Key ?? row.multipartStartResponse?.key;
    final uploadId =
        session?.s3UploadId ?? row.multipartStartResponse?.uploadId;
    if (key == null || uploadId == null) return;

    debugPrint(
      "📋 UploadQueueManager: Aborting multipart upload for upload ${row.id}",
    );
    await UploadRepo.abortMultipartUpload(key: key, uploadId: uploadId);
  }

  void _removeUploadFromQueueState(int id) {
    _pendingQueue = _pendingQueue.where((u) => u.id != id).toList();
    if (_batchUploadIds.remove(id) && _batchTotalCount > 0) {
      _batchTotalCount -= 1;
    }
    _networkFailedUploadIds.remove(id);
    _cooldownUntil.remove(id);
    _pausedUploadIds.remove(id);
    if (_pauseRequestedForUploadId == id) {
      _pauseRequestedForUploadId = null;
      if (!_isPaused) _uploadService.clearPause();
    }
    if (_currentUpload?.id == id) {
      _currentUpload = null;
    }
  }

  void _deleteRecordingFiles(Upload upload) {
    try {
      final sessionDir = Directory(p.dirname(upload.filepath));
      if (p.basename(sessionDir.path).startsWith("session_") &&
          sessionDir.existsSync()) {
        debugPrint(
          "🗑️ UploadQueueManager: Deleting session directory ${sessionDir.path}",
        );
        sessionDir.deleteSync(recursive: true);
      }
    } catch (e) {
      debugPrint("⚠️ UploadQueueManager: Failed to delete recording files: $e");
    }
  }

  Future<void> _deleteRecordingDirectory(Upload upload) async {
    try {
      final resolvedPath = await ResolveFilePath.resolve(upload.filepath);
      final sessionDir = Directory(resolvedPath).parent;
      if (await sessionDir.exists()) {
        debugPrint(
          "🗑️ UploadQueueManager: Deleting recording directory ${sessionDir.path}",
        );
        await sessionDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint(
        "⚠️ UploadQueueManager: Failed to delete recording directory: $e",
      );
    }
  }

  @override
  void dispose() {
    _pendingDbNotifyTimer?.cancel();
    _cooldownTimer?.cancel();
    _stopWatching();
    super.dispose();
  }

  void reset() {
    _pendingDbNotifyTimer?.cancel();
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _lastDbNotifyTime = null;
    _stopWatching();
    _isProcessing = false;
    _isCancelling = false;
    _isPaused = false;
    _uploadService.clearPause();
    _currentUpload = null;
    _pendingQueue = [];
    _errors.clear();
    _batchUploadIds.clear();
    _networkFailedUploadIds.clear();
    _cooldownUntil.clear();
    _pausedUploadIds.clear();
    _pauseRequestedForUploadId = null;
    _batchTotalCount = 0;
    _batchCompletedCount = 0;
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ARCHITECTURE OVERVIEW
// ═════════════════════════════════════════════════════════════════════════════
//
// UploadQueueManager is a singleton that manages the lifecycle of video uploads.
// It provides a unified queue system with automatic resumption, progress-based
// prioritization, and batch tracking.
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │                           COMPONENT FLOW                                │
// ├─────────────────────────────────────────────────────────────────────────┤
// │                                                                         │
// │  1. ENTRY POINT: processQueue()                                         │
// │     └─> Single method to start/resume uploads                           │
// │     └─> Can pass newUploads or rely on DB state                         │
// │                                                                         │
// │  2. DATABASE WATCHER                                                    │
// │     └─> Subscribes to UploadDb.watch() stream                           │
// │     └─> Filters uploads with status: pending OR uploading               │
// │     └─> Sorts by progress DESC (highest progress first)                 │
// │     └─> Updates _pendingQueue and triggers processing                   │
// │                                                                         │
// │  3. SEQUENTIAL PROCESSING                                               │
// │     └─> Processes uploads one-by-one via _processNext()                 │
// │     └─> Tracks videoIndex (1/5, 2/5, etc.) for notifications            │
// │     └─> Calls UploadsService.uploadFile() for each upload               │
// │     └─> Handles success/failure via callbacks                           │
// │                                                                         │
// │  4. BATCH TRACKING                                                      │
// │     └─> _batchUploadIds: Set of upload IDs in current batch             │
// │     └─> _batchTotalCount: Initial count when batch starts               │
// │     └─> _batchCompletedCount: Number processed (success + failure)      │
// │     └─> successfulUploads: List of successful uploads for notification  │
// │                                                                         │
// │  5. COMPLETION HANDLING                                                 │
// │     └─> When queue empties, checks if batch is complete                 │
// │     └─> If all uploads in batch are done, shows notification            │
// │     └─> Calls onBatchComplete() callback with successful uploads        │
// │     └─> Clears batch tracking for next batch                            │
// │                                                                         │
// └─────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │                          KEY DESIGN DECISIONS                           │
// ├─────────────────────────────────────────────────────────────────────────┤
// │                                                                         │
// │  • REACTIVE STATE: Uses ChangeNotifier for UI updates                   │
// │  • DB-DRIVEN: Queue state is derived from database, not in-memory       │
// │  • AUTO-RESUME: Picks up uploads with progress > 0 automatically        │
// │  • PRIORITY: Uploads closest to completion are processed first          │
// │  • BATCH AWARE: Tracks which uploads belong to current batch            │
// │  • SINGLE ENTRY: processQueue() is the only way to start processing     │
// │                                                                         │
// └─────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │                            STATE VARIABLES                              │
// ├─────────────────────────────────────────────────────────────────────────┤
// │                                                                         │
// │  _isProcessing          Whether actively processing uploads             │
// │  _isWatching            Whether DB subscription is active               │
// │  _currentUpload         Upload currently being processed                │
// │  _pendingQueue          Uploads waiting to be processed (from DB)       │
// │  _errors                Errors from current batch                       │
// │  _batchUploadIds        IDs of uploads in current batch                 │
// │  _batchTotalCount       Total uploads when batch started                │
// │  _batchCompletedCount   Number of uploads completed in batch            │
// │  successfulUploads      Uploads that completed successfully             │
// │                                                                         │
// └─────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │                           USAGE EXAMPLES                                │
// ├─────────────────────────────────────────────────────────────────────────┤
// │                                                                         │
// │  // Start processing user-selected uploads                             │
// │  queueManager.processQueue(newUploads: selectedUploads);                │
// │                                                                         │
// │  // Resume on app start (auto-picks up incomplete uploads)             │
// │  queueManager.processQueue();                                           │
// │                                                                         │
// │  // Add callbacks for events                                           │
// │  queueManager.onBatchComplete = (uploads) {                             │
// │    showCompletionBottomSheet(uploads);                                  │
// │  };                                                                     │
// │                                                                         │
// │  // Control queue                                                       │
// │  queueManager.pause();                                                  │
// │  queueManager.resume();                                                 │
// │  queueManager.cancelAll();                                              │
// │  queueManager.retry(failedUpload);                                      │
// │                                                                         │
// └─────────────────────────────────────────────────────────────────────────┘
