import "dart:async";
import "dart:convert";
import "dart:io";

import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/ar_recorder/helpers/ar_recorder_launcher.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_unsupported_device_bottom_sheet.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/home/data/models/video_metadata.dart";
import "package:stera/src/modules/upload/providers/managers/upload_selection_manager.dart";
import "package:stera/src/modules/upload/ui/widgets/duplicate_videos_bottomsheet.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/upload_service/utils/mcap_finalization.dart";
import "package:stera/src/services/upload_service/utils/resolve_file_path.dart";
import "package:stera/src/services/video_picker_service/video_picker_service.dart";
import "package:drift/drift.dart" hide Column;
import "package:path_provider/path_provider.dart";
import "package:flutter/material.dart" hide Column;
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

class VideoSourceManager extends ChangeNotifier {
  bool _loading = false;
  bool get loading => _loading;
  set loading(bool value) {
    _loading = value;
    notifyListeners();
  }

  final List<String> _dupUris = <String>[];
  List<String> get dupUris => _dupUris;
  set dupUris(List<String> value) {
    _dupUris.clear();
    _dupUris.addAll(value);
    notifyListeners();
  }

  void addDupUri(String uri) {
    _dupUris.add(uri);
    notifyListeners();
  }

  void clearDupUris() {
    _dupUris.clear();
    notifyListeners();
  }

  Future<(List<Upload>, List<Failure>?)> recordVideos({
    required List<VideoMetadata> existingVideos,
    String? parentTaskId,
    String? parentTaskName,
    String? subtaskId,
    String? subtaskName,
  }) async {
    loading = true;

    // `recordVideosForUpload` already ran the Android AR-availability check
    // before its network calls, so the launcher skips it here rather than
    // showing the unsupported-device sheet a second time on the same tap.
    final (sessionDir, launchFailure) = await ArRecorderLauncher.launch(
      null,
      checkArSupport: false,
    );

    if (sessionDir == null) {
      loading = false;
      return (<Upload>[], launchFailure == null ? null : [launchFailure]);
    }

    final (upload, failure) = await createUploadFromSessionDir(
      sessionDir: sessionDir,
      parentTaskId: parentTaskId,
      parentTaskName: parentTaskName,
      subtaskId: subtaskId,
      subtaskName: subtaskName,
      source: "upload_flow",
    );
    loading = false;
    if (upload != null) {
      return ([upload], null);
    }
    return (<Upload>[], failure == null ? null : [failure]);
  }

  /// Builds an [Upload] DB row for an AR session directory and inserts it.
  /// Used by both the single-device record flow (`recordVideos`) and the
  /// recorder finalize handler in ArRecorderPage — both end up
  /// with a session dir on disk and need the same DB-side bookkeeping so
  /// the recording shows up in `NotStartedVideosGridView`.
  Future<(Upload?, Failure?)> createUploadFromSessionDir({
    required String sessionDir,
    String? parentTaskId,
    String? parentTaskName,
    String? subtaskId,
    String? subtaskName,
    String source = "ar_session",
  }) async {
    try {
      // Find session_data_*.mcap in the session directory.
      // Finalization runs in the background, so poll until the mcap is
      // actually FINALIZED (trailing MCAP magic present — see
      // [McapFinalization]), up to 60 seconds. metadata.json alone is not a
      // completion marker: native writes it BEFORE the mcap footer, and for
      // long recordings the footer is the slow step. Snapshotting the size of
      // a still-growing mcap froze a truncated chunk plan — the upload then
      // "completed" but the object was truncated/empty and unverifiable.
      final sessionDirectory = Directory(sessionDir);
      final metadataFile = File("$sessionDir/metadata.json");
      File? mcapFile;
      bool metadataReady = false;
      bool mcapFinalized = false;
      for (var attempt = 0; attempt < 120; attempt++) {
        mcapFile = sessionDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .cast<File?>()
            .firstWhere(
              (f) =>
                  f!.uri.pathSegments.last.startsWith("session_data_") &&
                  f.uri.pathSegments.last.endsWith(".mcap"),
              orElse: () => null,
            );
        metadataReady =
            await metadataFile.exists() && (await metadataFile.length()) > 0;
        mcapFinalized =
            mcapFile != null && await McapFinalization.isFinalized(mcapFile);
        // metadata.json is written before the mcap footer, so once the mcap
        // is finalized a missing metadata file means the native write failed
        // — no point waiting for it.
        if (mcapFinalized) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (mcapFile == null) {
        return (
          null,
          Failure(
            code: ErrorType.unknown,
            message: "session_data mcap not found in $sessionDir",
          ),
        );
      }

      if (!mcapFinalized) {
        // Still finalizing (or crash-truncated). Do NOT create a row off a
        // growing file — the OrphanRecoverySweeper / recover button adopts
        // the session once the trailing magic lands.
        debugPrint(
          "⚠️ createUploadFromSessionDir: mcap not finalized after polling — "
          "deferring to orphan recovery ($sessionDir)",
        );
        return (
          null,
          Failure(
            code: ErrorType.uploadInComplete,
            message:
                "Your recording is still processing — it will appear in "
                "uploads once it's ready.",
          ),
        );
      }

      if (!metadataReady) {
        debugPrint(
          "⚠️ metadata.json not found after polling — proceeding without it",
        );
      }

      final mcapFileName = mcapFile.uri.pathSegments.last;

      // Store paths with documents:// scheme so they survive iOS container
      // UUID changes between app restarts/reinstalls.
      final mcapUri = await ResolveFilePath.toDocumentsUri(mcapFile.path);
      final metadataUri = await ResolveFilePath.toDocumentsUri(
        metadataFile.path,
      );

      int? durationMs;
      if (await metadataFile.exists()) {
        try {
          final metadata =
              jsonDecode(await metadataFile.readAsString())
                  as Map<String, dynamic>;
          durationMs = _durationMsFromMetadata(metadata);
        } catch (e) {
          debugPrint("Failed to read AR metadata: $e");
        }
      }

      final thumbnailFile = File("$sessionDir/thumbnail.jpg");
      String? thumbnailUri;
      if (await thumbnailFile.exists()) {
        thumbnailUri = await ResolveFilePath.toDocumentsUri(thumbnailFile.path);
      }

      final fileSize = await mcapFile.length();

      // Guard against double-inserting the same session — the recovery
      // path can race the single-device fallback (e.g. orphan recovery) on
      // the same dir.
      final exists = await UploadDb.instance.checkIfExists(
        filePath: mcapUri,
        status: UploadStatus.values,
      );
      if (exists) {
        debugPrint(
          "createUploadFromSessionDir: upload row already exists for $mcapUri",
        );
        return (null, null);
      }

      final uploadCompanion = UploadsCompanion.insert(
        filepath: mcapUri,
        filesize: Value(fileSize),
        durationMs: Value(durationMs),
        thumnbnail: Value(thumbnailUri),
        metadataFilepath: Value(metadataUri),
        status: const Value(UploadStatus.notStarted),
        fileName: Value(mcapFileName),
        mimeType: const Value("application/octet-stream"),
        taskId: Value(parentTaskId),
        taskName: Value(parentTaskName),
        subtaskId: Value(subtaskId),
        subtaskName: Value(subtaskName),
      );

      final upload = await UploadDb.instance.add(
        mcapUri,
        uploadCompanion: uploadCompanion,
      );
      return (upload, null);
    } catch (e) {
      return (null, Failure.fromException(e));
    }
  }

  Future<(List<Upload>, List<Failure>?)> pickVideos({
    required List<VideoMetadata> existingVideos,
    String? parentTaskId,
    String? parentTaskName,
    String? subtaskId,
    String? subtaskName,
  }) async {
    loading = true;

    final uris = await VideoPickerService.instance.pickVideos();

    if (uris == null || uris.isEmpty) {
      loading = false;
      return (<Upload>[], null);
    }

    final List<Failure> errors = <Failure>[];
    final List<Upload> uploads = <Upload>[];

    for (final uri in uris) {
      final (upload, err) = await VideoPickerService.instance.createUpload(
        uriString: uri,
        existingVideos: existingVideos,
        parentTaskId: parentTaskId,
        parentTaskName: parentTaskName,
        subtaskId: subtaskId,
        subtaskName: subtaskName,
      );
      if (err != null) {
        if (err.code == ErrorType.duplicateUpload) {
          addDupUri(uri);
        }
        errors.add(err);
      } else if (upload != null) {
        uploads.add(upload);
      }
    }

    loading = false;

    return (uploads, errors.isEmpty ? null : errors);
  }

  void reset() {
    loading = false;
  }

  /// Scans `<Documents>/ar_sessions/` for AR session folders that exist on
  /// disk but have no row in the uploads table, and inserts them as
  /// [UploadStatus.notStarted]. Used after sign-in to recover recordings
  /// orphaned by reinstalls or DB resets.
  Future<List<Upload>> recoverOrphanedSessions() async {
    loading = true;
    final List<Upload> recovered = <Upload>[];

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final arRoot = Directory("${docsDir.path}/ar_sessions");
      if (!await arRoot.exists()) {
        loading = false;
        return recovered;
      }

      final sessionDirs = arRoot
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last
              .startsWith("session_"));

      for (final sessionDir in sessionDirs) {
        try {
          final mcapFile = sessionDir
              .listSync(followLinks: false)
              .whereType<File>()
              .cast<File?>()
              .firstWhere(
                (f) =>
                    f!.uri.pathSegments.last.startsWith("session_data_") &&
                    f.uri.pathSegments.last.endsWith(".mcap"),
                orElse: () => null,
              );

          if (mcapFile == null || !await mcapFile.exists()) continue;
          // Never adopt a still-finalizing (or crash-truncated) mcap: its
          // size snapshot would freeze a truncated chunk plan and upload a
          // broken file. Finalization writes the trailing magic last, so a
          // later sweep/recover picks the session up once it's complete.
          if (!await McapFinalization.isFinalized(mcapFile)) {
            debugPrint(
              "recoverOrphanedSessions: skipping ${sessionDir.path} — "
              "mcap not finalized (still writing or truncated)",
            );
            continue;
          }
          final fileSize = await mcapFile.length();
          if (fileSize <= 0) continue;

          final mcapUri = await ResolveFilePath.toDocumentsUri(mcapFile.path);

          final exists = await UploadDb.instance.checkIfExists(
            filePath: mcapUri,
            status: UploadStatus.values,
          );
          if (exists) continue;

          final metadataFile = File("${sessionDir.path}/metadata.json");
          int? durationMs;
          String? metadataUri;
          if (await metadataFile.exists()) {
            metadataUri = await ResolveFilePath.toDocumentsUri(
              metadataFile.path,
            );
            try {
              final metadata =
                  jsonDecode(await metadataFile.readAsString())
                      as Map<String, dynamic>;
              durationMs = _durationMsFromMetadata(metadata);
            } catch (e) {
              debugPrint("recoverOrphanedSessions: bad metadata.json: $e");
            }
          }

          final thumbnailFile = File("${sessionDir.path}/thumbnail.jpg");
          String? thumbnailUri;
          if (await thumbnailFile.exists()) {
            thumbnailUri = await ResolveFilePath.toDocumentsUri(
              thumbnailFile.path,
            );
          }

          final mcapFileName = mcapFile.uri.pathSegments.last;

          final companion = UploadsCompanion.insert(
            filepath: mcapUri,
            filesize: Value(fileSize),
            durationMs: Value(durationMs),
            thumnbnail: Value(thumbnailUri),
            metadataFilepath: Value(metadataUri),
            status: const Value(UploadStatus.notStarted),
            fileName: Value(mcapFileName),
            mimeType: const Value("application/octet-stream"),
          );

          final upload = await UploadDb.instance.add(
            mcapUri,
            uploadCompanion: companion,
          );
          recovered.add(upload);
        } catch (e) {
          debugPrint(
            "recoverOrphanedSessions: skipping ${sessionDir.path}: $e",
          );
        }
      }
    } catch (e) {
      debugPrint("recoverOrphanedSessions: $e");
    }

    loading = false;
    return recovered;
  }

  /// AR check (Android), user refresh, load videos, then native record flow and
  /// merge into the upload queue (same flow as “Record” on add upload).
  Future<void> recordVideosForUpload(
    BuildContext context,
    UploadSelectionManager selection,
  ) async {
    final uvp = context.read<UploadedVideosProvider>();
    final ap = context.read<AuthProvider>();

    loading = true;

    await Future<void>.delayed(const Duration(seconds: 1));

    if (Platform.isAndroid) {
      final isArSupported = await ArRecorderService.checkArAvailability();
      if (!isArSupported) {
        loading = false;
        if (context.mounted) {
          await showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => const ArUnsupportedDeviceBottomSheet(),
          );
        }
        return;
      }
    }

    if (ap.user == null) await ap.forceRefreshUser();

    if (!context.mounted) {
      loading = false;
      return;
    }

    if (uvp.videos.isEmpty) {
      await uvp.getUploadedVideos();
    }

    final (uploads, errors) = await recordVideos(existingVideos: uvp.videos);
    await handleUploadResult(selection, uploads, errors);
  }

  Future<void> handleUploadResult(
    UploadSelectionManager selection,
    List<Upload> uploads,
    List<Failure>? errors,
  ) async {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    // Select all successfully added uploads
    for (final upload in uploads) {
      selection.selectUpload(upload);
    }

    // Show dialog if there are duplicates
    if (dupUris.isNotEmpty) {
      await DuplicateVideosBottomSheet.show(
        context: context,
        dupUris: List.from(dupUris),
        onConfirm: () {
          clearDupUris();
        },
      );
    }

    // Handle other errors
    if (errors != null) {
      for (final error in errors) {
        if (error.code != ErrorType.duplicateUpload) {
          AppToast.show(title: error.message, appToastType: AppToastType.error);
        }
      }
    }
  }

  static int? _durationMsFromMetadata(Map<String, dynamic> metadata) {
    for (final key in ["session_duration_seconds", "durationSeconds"]) {
      final durationSeconds = _numToDouble(metadata[key]);
      if (durationSeconds == null) continue;

      final durationMs = _sanitizeDurationMs(durationSeconds);
      if (durationMs != null) return durationMs;
    }

    return _durationMsFromStreamDurations(metadata["stream_durations_ms"]);
  }

  static int? _durationMsFromStreamDurations(Object? value) {
    if (value is! Map) return null;

    const preferredStreams = ["rgb", "pose", "depth", "pointcloud", "imu"];
    for (final stream in preferredStreams) {
      final durationMs = _numToDouble(value[stream]);
      if (durationMs == null) continue;

      final sanitized = _sanitizeDurationMs(durationMs / 1000);
      if (sanitized != null) return sanitized;
    }

    int? longestDurationMs;
    for (final duration in value.values) {
      final durationMs = _numToDouble(duration);
      if (durationMs == null) continue;

      final sanitized = _sanitizeDurationMs(durationMs / 1000);
      if (sanitized == null) continue;
      if (longestDurationMs == null || sanitized > longestDurationMs) {
        longestDurationMs = sanitized;
      }
    }

    return longestDurationMs;
  }

  static double? _numToDouble(Object? value) {
    return value is num ? value.toDouble() : null;
  }

  /// Clamps a metadata-reported duration to a sane range.
  /// Returns null when the value is non-positive or obviously bogus. A real
  /// AR session won't exceed `_maxPlausibleDurationSeconds`; a value above
  /// it indicates corrupt metadata (most commonly an epoch leak from the
  /// native finalize path where the duration ended up = current Unix time).
  static int? _sanitizeDurationMs(double durationSeconds) {
    if (!durationSeconds.isFinite) return null;
    if (durationSeconds <= 0) return null;
    if (durationSeconds > _maxPlausibleDurationSeconds) {
      debugPrint(
        "⚠️ VideoSourceManager: implausible session_duration_seconds=$durationSeconds, dropping",
      );
      return null;
    }
    return (durationSeconds * 1000).toInt();
  }

  static const double _maxPlausibleDurationSeconds = 12 * 60 * 60; // 12h
}
