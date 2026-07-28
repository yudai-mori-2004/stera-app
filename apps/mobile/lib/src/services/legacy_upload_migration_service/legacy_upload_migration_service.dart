import "dart:io";
import "package:drift/drift.dart";
import "package:flutter/foundation.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/upload_service/chunk_plan/upload_chunk_planner.dart";

/// Safe entrypoint for legacy upload migration.
///
/// Runs only on iOS, never throws, and shares concurrent calls.
class LegacyUploadMigrationService {
  LegacyUploadMigrationService._internal();

  static final LegacyUploadMigrationService _instance =
      LegacyUploadMigrationService._internal();
  static LegacyUploadMigrationService get instance => _instance;

  Future<int>? _inFlight;

  /// Migrates idle legacy uploads. Returns 0 on non-iOS or failure.
  Future<int> run() {
    if (!Platform.isIOS) return Future.value(0);
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<int> _run() async {
    try {
      final migrated = await LegacyUploadMigrator().migrateIdleRows();
      if (migrated > 0) {
        debugPrint("✅ legacy upload migration: $migrated row(s) migrated");
      }
      return migrated;
    } catch (e) {
      debugPrint("⚠️ legacy upload migration failed (non-fatal): $e");
      return 0;
    }
  }
}

/// Migrates legacy `uploads` rows into `upload_sessions` and `upload_parts`.
///
/// Only idle rows are migrated. Uploading rows stay on the legacy path. The
/// migration is idempotent because each row maps to `legacy-<rowId>`.
class LegacyUploadMigrator {
  LegacyUploadMigrator({AppDatabase? db, this.chunkSize = legacyChunkSize})
    : db = db ?? AppDatabase.instance;

  final AppDatabase db;
  final int chunkSize;

  /// The 30 MB chunk size used by the legacy path.
  static const int legacyChunkSize = 30 * 1024 * 1024;

  /// Statuses safe to migrate.
  static const Set<UploadStatus> migratableStatuses = {
    UploadStatus.pending,
    UploadStatus.notStarted,
    UploadStatus.failed,
    UploadStatus.paused,
  };

  static String sessionIdFor(Upload row) => "legacy-${row.id}";

  static SessionState mapStatus(UploadStatus status) => switch (status) {
    UploadStatus.completed => SessionState.completed,
    UploadStatus.cancelled => SessionState.cancelled,
    UploadStatus.failed => SessionState.failedTerminal,
    UploadStatus.paused => SessionState.paused,
    UploadStatus.uploading => SessionState.transferring,
    UploadStatus.pending => SessionState.queued,
    UploadStatus.notStarted => SessionState.queued,
  };

  /// Builds session and part rows for a legacy upload.
  ({UploadSessionsCompanion session, List<UploadPartsCompanion> parts})?
  buildFor(Upload row) {
    final fileSize = row.filesize;
    if (fileSize == null || fileSize <= 0) return null;

    final id = sessionIdFor(row);
    final start = row.multipartStartResponse;
    final partCount =
        row.partsCount ??
        UploadChunkPlanner.partCountFor(
          fileSize: fileSize,
          chunkSize: chunkSize,
        );

    final session = UploadSessionsCompanion.insert(
      id: id,
      filepath: row.filepath,
      fileSize: fileSize,
      fileName: row.fileName ?? _basename(row.filepath),
      mimeType: row.mimeType ?? "application/octet-stream",
      durationMs: Value(row.durationMs),
      thumbnailPath: Value(row.thumnbnail),
      metadataFilepath: Value(row.metadataFilepath),
      chunkSize: Value(chunkSize),
      partCount: Value(partCount),
      s3Key: Value(start?.key),
      s3UploadId: Value(start?.uploadId),
      assetId: Value(start?.videoId),
      state: Value(mapStatus(row.status)),
      taskId: Value(row.taskId),
      subtaskId: Value(row.subtaskId),
    );

    final etagByPart = <int, String>{
      for (final p in (row.uploadedParts ?? const [])) p.partNumber: p.etag,
    };
    final plan = UploadChunkPlanner.plan(
      fileSize: fileSize,
      chunkSize: chunkSize,
    );
    final parts = [
      for (final entry in plan)
        UploadPartsCompanion.insert(
          sessionId: id,
          partNumber: entry.partNumber,
          offset: entry.offset,
          length: entry.length,
          state: etagByPart.containsKey(entry.partNumber)
              ? const Value(PartState.uploaded)
              : const Value(PartState.planned),
          etag: Value(etagByPart[entry.partNumber]),
        ),
    ];

    return (session: session, parts: parts);
  }

  /// Migrates idle legacy rows that have not already been migrated.
  Future<int> migrateIdleRows() async {
    final legacy = await db.select(db.uploads).get();
    var migrated = 0;

    for (final row in legacy) {
      if (!migratableStatuses.contains(row.status)) continue;

      final id = sessionIdFor(row);
      final already = await (db.select(
        db.uploadSessions,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      if (already != null) continue;

      final built = buildFor(row);
      if (built == null) continue;

      await db.transaction(() async {
        await db.into(db.uploadSessions).insert(built.session);
        if (built.parts.isNotEmpty) {
          await db.batch((b) => b.insertAll(db.uploadParts, built.parts));
        }
      });
      migrated++;
    }

    return migrated;
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf("/");
    return slash >= 0 ? path.substring(slash + 1) : path;
  }
}
