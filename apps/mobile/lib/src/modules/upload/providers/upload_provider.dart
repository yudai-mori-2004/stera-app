import "dart:async";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/upload/providers/managers/upload_progress_manager.dart";
import "package:stera/src/modules/upload/providers/managers/upload_queue_manager.dart";
import "package:stera/src/modules/upload/providers/managers/upload_selection_manager.dart";
import "package:stera/src/modules/upload/providers/managers/video_source_manager.dart";
import "package:stera/src/services/upload_service/data/typedef/upload_progress.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_success_bottomsheet/upload_success_bottomsheet.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/upload_service/channels/upload_foreground_notifier.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/upload_service/utils/resolve_file_path.dart";
import "package:drift/drift.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class UploadProvider extends ChangeNotifier {
  UploadProvider() {
    loading = true;
    watchUploads();
    selection.addListener(notifyListeners);
    picker.addListener(notifyListeners);
    setupQueueManager();
    _progressManager.addListener(notifyListeners);

    // Resume any pending uploads on app start
    _resumePendingUploadsOnStart();
  }

  final UploadSelectionManager _selectionManager = UploadSelectionManager();
  UploadSelectionManager get selection => _selectionManager;

  final UploadQueueManager _queueManager = UploadQueueManager.instance;
  UploadQueueManager get queueManager => _queueManager;

  final VideoSourceManager _picker = VideoSourceManager();
  VideoSourceManager get picker => _picker;

  final UploadProgressManager _progressManager = UploadProgressManager.instance;
  UploadProgressManager get progressManager => _progressManager;

  /// Current upload progress from the progress manager
  UploadProgress? get currentProgress => _progressManager.currentProgress;

  /// Live time-remaining estimate for the upload in flight, based on the
  /// observed network speed. `null` when nothing is uploading or no speed
  /// is known yet.
  Duration? get currentEta => _progressManager.currentEta;

  StreamSubscription<List<Upload>>? _uploadSubscription;

  final db = UploadDb.instance;

  bool _loading = false;
  bool get loading => _loading;
  set loading(bool value) {
    _loading = value;
    notifyListeners();
  }

  final Map<int, Upload> _uploadsMap = {};
  Map<int, Upload> get uploadsMap => _uploadsMap;

  /// Get all uploads sorted by: pending/uploading first, then by progress descending
  List<Upload> get allUploads {
    final uploads = _uploadsMap.values.toList();

    // Sort: active uploads first (pending/uploading), then by progress descending
    uploads.sort((a, b) {
      final aIsActive =
          a.status == UploadStatus.pending ||
          a.status == UploadStatus.uploading;
      final bIsActive =
          b.status == UploadStatus.pending ||
          b.status == UploadStatus.uploading;

      // Active uploads come first
      if (aIsActive && !bIsActive) return -1;
      if (!aIsActive && bIsActive) return 1;

      // Within same category, sort by progress descending
      final progressA = a.progress ?? 0;
      final progressB = b.progress ?? 0;
      return progressB.compareTo(progressA);
    });

    return uploads;
  }

  /// Get only pending/uploading uploads
  List<Upload> get pendingUploads => _uploadsMap.values
      .where(
        (u) =>
            u.status == UploadStatus.pending ||
            u.status == UploadStatus.uploading,
      )
      .toList();

  Upload? getUpload(int id) => _uploadsMap[id];

  List<Upload> get selectedUploads => selection.selectedIds
      .map((id) => _uploadsMap[id])
      .whereType<Upload>()
      .toList();

  void setupQueueManager() {
    queueManager.onBatchComplete = _showCompletionBottomSheet;
    queueManager.addListener(notifyListeners);
  }

  /// Resumes any pending or in-progress uploads when the app starts.
  /// This ensures uploads continue after app restart or being killed.
  Future<void> _resumePendingUploadsOnStart() async {
    // Wait a bit for the database to be ready and uploads to be loaded
    await Future.delayed(const Duration(milliseconds: 500));

    // Fix stale absolute iOS paths by converting them to documents:// scheme
    await _fixStaleFilePaths();

    // Get all pending and uploading uploads from the database
    final pendingUploads = await db.getByStatus(UploadStatus.pending);
    final uploadingUploads = await db.getByStatus(UploadStatus.uploading);

    final uploadsToResume = [...pendingUploads, ...uploadingUploads];

    if (uploadsToResume.isNotEmpty) {
      debugPrint(
        "🚀 UploadProvider: Resuming ${uploadsToResume.length} pending uploads on app start",
      );

      // Clear any paused state from previous session
      queueManager.clearPauseState();

      // Start processing the queue with the pending uploads
      queueManager.processQueue(newUploads: uploadsToResume);
    }
  }

  /// Converts stale absolute iOS paths to documents:// scheme.
  /// This handles uploads created before the documents:// scheme was introduced,
  /// or uploads whose absolute paths became invalid due to iOS container UUID changes.
  Future<void> _fixStaleFilePaths() async {
    final allStatuses = [
      UploadStatus.notStarted,
      UploadStatus.pending,
      UploadStatus.uploading,
      UploadStatus.failed,
      UploadStatus.paused,
    ];

    for (final status in allStatuses) {
      final uploads = await db.getByStatus(status);
      for (final upload in uploads) {
        // Skip if already using documents:// scheme
        if (upload.filepath.startsWith("documents://")) continue;

        // Try to convert absolute path to documents:// URI
        final documentsUri = await ResolveFilePath.toDocumentsUri(
          upload.filepath,
        );
        if (documentsUri != upload.filepath) {
          debugPrint(
            "🔧 UploadProvider: Converting stale path to documents:// for upload ${upload.id}",
          );
          await db.update(upload.id, upload.copyWith(filepath: documentsUri));

          // Also fix thumbnail path if present
          if (upload.thumnbnail != null &&
              !upload.thumnbnail!.startsWith("documents://")) {
            final thumbUri = await ResolveFilePath.toDocumentsUri(
              upload.thumnbnail!,
            );
            if (thumbUri != upload.thumnbnail) {
              await db.update(
                upload.id,
                upload.copyWith(thumnbnail: Value(thumbUri)),
              );
            }
          }
        }
      }
    }
  }

  Future<Failure?> startUploads() async {
    final navContext = AppRouter.navigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      final ap = navContext.read<AuthProvider>();
      if (ap.user == null) await ap.forceRefreshUser();
    }

    final uploadsToProcess = List<Upload>.from(selectedUploads);

    if (uploadsToProcess.isEmpty) {
      debugPrint(
        "⚠️ UploadProvider: startUploads — empty selection (stale IDs?)",
      );
      return Failure(
        code: ErrorType.validation,
        message: "No uploads selected. Please select at least one video.",
      );
    }

    debugPrint(
      "🚀 UploadProvider: startUploads — ${uploadsToProcess.length} selected",
    );

    // Await all DB updates to ensure statuses are 'pending' before the queue
    // manager starts watching. Without this, the DB watcher may fire before
    // the status transitions, leaving the pending queue empty.
    for (Upload upload in uploadsToProcess) {
      await db.update(upload.id, upload.copyWith(status: UploadStatus.pending));
    }

    // Re-fetch updated uploads so the queue manager receives the correct status
    final updatedUploads = <Upload>[];
    for (final upload in uploadsToProcess) {
      final updated = await db.getById(upload.id);
      if (updated != null) updatedUploads.add(updated);
    }

    if (updatedUploads.length != uploadsToProcess.length) {
      debugPrint(
        "⚠️ UploadProvider: startUploads — refetch mismatch "
        "(${updatedUploads.length}/${uploadsToProcess.length})",
      );
      return Failure(
        code: ErrorType.validation,
        message: "Could not load selected uploads. Please try again.",
      );
    }

    final allPendingOrUploading = updatedUploads.every(
      (u) =>
          u.status == UploadStatus.pending ||
          u.status == UploadStatus.uploading,
    );
    if (!allPendingOrUploading) {
      debugPrint(
        "⚠️ UploadProvider: startUploads — rows not pending after update",
      );
      return Failure(
        code: ErrorType.validation,
        message: "Could not prepare uploads for upload. Please try again.",
      );
    }

    // Fresh submit must not be blocked by a paused queue from a prior session.
    queueManager.clearPauseState();
    await UploadForegroundNotifier.start(totalVideos: updatedUploads.length);

    final error = queueManager.processQueue(newUploads: updatedUploads);

    if (error != null) {
      debugPrint(
        "⚠️ UploadProvider: startUploads — queue did not start: ${error.message}",
      );
      return error;
    }


    debugPrint(
      "✅ UploadProvider: startUploads — enqueued ${updatedUploads.length}, "
      "processing kicked",
    );
    selection.clearSelection();
    return null;
  }

  void watchUploads() {
    _uploadSubscription = db.watch().listen(
      _onUploadsChanged,
      onError: (Object error, StackTrace st) {
        // A failure here means the database stream never delivered (e.g. the
        // schema migration threw and the DB couldn't open). Drop the loading
        // gate so the UI renders the empty state instead of hanging forever on
        // the spinner, and surface the error for diagnosis.
        debugPrint("⚠️ UploadProvider: uploads watch errored: $error");
        if (loading) loading = false;
      },
    );
  }

  void _onUploadsChanged(List<Upload> allUploads) {
    // Get IDs of uploads currently in the database
    final currentIds = allUploads.map((u) => u.id).toSet();

    // Remove uploads that are no longer in the database
    final idsToRemove = _uploadsMap.keys
        .where((id) => !currentIds.contains(id))
        .toList();
    for (final id in idsToRemove) {
      _uploadsMap.remove(id);
    }

    // Add or update uploads from the database, tracking which rows are newly
    // appearing on this tick.
    final newlyAdded = <Upload>[];
    for (final upload in allUploads) {
      final existing = _uploadsMap[upload.id];

      if (existing == null || existing != upload) {
        _uploadsMap[upload.id] = upload;
      }
      if (existing == null) newlyAdded.add(upload);
    }

    final selectableNotStarted = allUploads
        .where(_isSelectableNotStarted)
        .toList();
    if (selectableNotStarted.length == 1) {
      _selectionManager.selectUploads(selectableNotStarted);
    } else {
      // Auto-select newly-added notStarted uploads, but only when there are
      // multiple candidates so we don't undo a user's manual de-selection.
      final newNotStarted = newlyAdded.where(_isSelectableNotStarted).toList();
      if (newNotStarted.isNotEmpty) {
        _selectionManager.selectUploads(newNotStarted);
      }
    }

    if (loading) {
      loading = false;
    }

    notifyListeners();
  }

  /// Shows the upload completion bottom sheet globally using the navigator key.
  void _showCompletionBottomSheet(List<Upload> completedUploads) {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }

    if (completedUploads.isEmpty) return;

    final uvp = context.read<UploadedVideosProvider>();

    uvp.getUploadedVideos();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          UploadSuccessBottomsheet(completedUploads: completedUploads),
    );
  }

  @override
  void dispose() {
    _progressManager.removeListener(notifyListeners);
    _progressManager.dispose();
    _queueManager.removeListener(notifyListeners);
    _uploadSubscription?.cancel();
    super.dispose();
  }

  void reset() {
    _uploadsMap.clear();
    loading = false;
    selection.clearSelection();
    picker.reset();
    queueManager.reset();
    _progressManager.reset();
  }

  bool _isSelectableNotStarted(Upload upload) {
    return !upload.isHidden &&
        upload.status == UploadStatus.notStarted &&
        ((upload.mimeType?.startsWith("video/") ?? false) ||
            upload.mimeType == "application/zip" ||
            upload.mimeType == "application/octet-stream");
  }
}
