import "dart:io";

import "package:flutter/foundation.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/schema/models/upload_part.dart";
import "package:drift/drift.dart";

class UploadDb {
  UploadDb._internal();
  static final UploadDb _instance = UploadDb._internal();
  static UploadDb get instance => _instance;

  /// Test-only override for [db]. Tests must clear this in tearDown.
  @visibleForTesting
  static AppDatabase? debugDatabase;

  AppDatabase get db => debugDatabase ?? AppDatabase.instance;

  Stream<List<Upload>> watch() => db.select(db.uploads).watch();

  Future<List<Upload>> get() => db.select(db.uploads).get();

  Future<Upload?> getById(int id) =>
      (db.select(db.uploads)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<List<Upload>> getByStatus(UploadStatus status) =>
      (db.select(db.uploads)..where((u) => u.status.equals(status.name))).get();

  /// Every row pointing at [filePath] (a `documents://` URI), in any state.
  ///
  /// Used by the retroactive hand-pose action to decide whether a session's
  /// bytes are safe to rewrite: the row caches `filesize`, so rewriting under
  /// one that is queued or in flight would upload new bytes against an old
  /// count.
  Future<List<Upload>> getByFilePath(String filePath) =>
      (db.select(db.uploads)..where((u) => u.filepath.equals(filePath))).get();

  Future<Upload> add(
    String filepath, {
    required UploadsCompanion uploadCompanion,
  }) async {
    final id = await db.into(db.uploads).insert(uploadCompanion);
    return (await getById(id))!;
  }

  Future<bool> checkIfExists({
    required String filePath,
    required List<UploadStatus> status,
  }) async {
    final count =
        await (db.select(db.uploads)..where(
              (u) =>
                  u.filepath.equals(filePath) &
                  u.status.isIn(status.map((s) => s.name).toList()),
            ))
            .get()
            .then((value) => value.length);
    return count > 0;
  }

  Future<int> update(int id, Upload data) =>
      (db.update(db.uploads)..where((u) => u.id.equals(id))).write(
        data.copyWith(updatedAt: DateTime.now()),
      );

  /// Writes only the status column. Use instead of [update] with a full row
  /// when the in-memory [Upload] may be stale — a full-row write would clobber
  /// columns (progress, uploadedParts, status) written concurrently elsewhere.
  Future<int> updateStatus(int id, UploadStatus status) =>
      (db.update(db.uploads)..where((u) => u.id.equals(id))).write(
        UploadsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Writes only the progress column (0..1). Used by the windowed engine path
  /// to persist a durable high-water mark so a cold relaunch renders the
  /// last-known progress instead of 0% (the tile's `upload.progress` fallback).
  /// Column-only so it never clobbers status/uploadedParts written elsewhere.
  Future<int> updateProgress(int id, double progress) =>
      (db.update(db.uploads)..where((u) => u.id.equals(id))).write(
        UploadsCompanion(
          progress: Value(progress),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Writes only the filesize column. Used by the upload service when the
  /// source file's on-disk size diverged from the row's snapshot (a row
  /// created while native finalization was still writing the mcap holds a
  /// truncated size — uploading off it truncates the object).
  Future<int> updateFilesize(int id, int filesize) =>
      (db.update(db.uploads)..where((u) => u.id.equals(id))).write(
        UploadsCompanion(
          filesize: Value(filesize),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Writes only progress + uploadedParts. Used by the chunk batch flusher so
  /// concurrent status changes (e.g. a user pausing the upload) survive.
  Future<int> updateUploadedParts(
    int id, {
    required List<UploadedPart> parts,
    required double progress,
  }) => (db.update(db.uploads)..where((u) => u.id.equals(id))).write(
    UploadsCompanion(
      progress: Value(progress),
      uploadedParts: Value(parts),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<int> cancel(Upload upload) =>
      update(upload.id, upload.copyWith(status: UploadStatus.cancelled));

  Future<int> delete(int id) async {
    final upload = await getById(id);
    if (upload?.thumnbnail != null) {
      final thumbnailFile = File(upload!.thumnbnail!);
      if (await thumbnailFile.exists()) {
        await thumbnailFile.delete();
      }
    }
    return (db.delete(db.uploads)..where((u) => u.id.equals(id))).go();
  }

  /// Prepares a failed upload for a manual retry while preserving multipart
  /// progress ([Upload.multipartStartResponse], [Upload.uploadedParts]) so the
  /// retry resumes from the last completed part instead of restarting at 0%.
  ///
  /// Only the status, retry budget, and presigned URLs are reset — URLs are
  /// refetched on the next attempt because they may have expired while the
  /// row sat in `failed`.
  ///
  /// Uses [UploadsCompanion] so [partUrls] is explicitly set to SQL NULL.
  /// A full [Upload] row with nulls omits those columns under Drift's update
  /// (`nullToAbsent`), leaving stale [partUrls] in the DB — retries then
  /// reuse dead presigned URLs (S3 404).
  Future<Upload?> prepareForRetry(int id) async {
    final existing = await getById(id);
    if (existing == null) return null;

    await (db.update(db.uploads)..where((u) => u.id.equals(id))).write(
      UploadsCompanion(
        status: const Value(UploadStatus.pending),
        retryCount: const Value(0),
        partUrls: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return getById(id);
  }

  /// Resets an upload to its pre-upload state while keeping the local file,
  /// thumbnail, and metadata intact. Clears all in-progress attempt data so
  /// the next upload starts fresh (new presign/multipart).
  ///
  /// Uses [UploadsCompanion] so nullable columns are explicitly set to SQL
  /// NULL — a full [Upload] row with nulls would omit them under Drift's
  /// `nullToAbsent` and leave stale presign/multipart data in the DB.
  Future<Upload?> resetToNotStarted(int id) async {
    final existing = await getById(id);
    if (existing == null) return null;

    await (db.update(db.uploads)..where((u) => u.id.equals(id))).write(
      UploadsCompanion(
        status: const Value(UploadStatus.notStarted),
        progress: const Value(null),
        retryCount: const Value(0),
        s3PresignResponse: const Value(null),
        multipartStartResponse: const Value(null),
        partUrls: const Value(null),
        uploadedParts: const Value(null),
        partsCount: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return getById(id);
  }

  Future<void> deleteCompletedUploads() async {
    final uploads = await getByStatus(UploadStatus.completed);
    for (final upload in uploads) {
      await delete(upload.id);
    }
  }

  Future<void> deleteCanceledUploads() async {
    final uploads = await getByStatus(UploadStatus.cancelled);
    for (final upload in uploads) {
      await delete(upload.id);
    }
  }

  Future<void> hideCompletedUploads() async {
    final uploads = await getByStatus(UploadStatus.completed);
    for (final upload in uploads) {
      await update(upload.id, upload.copyWith(isHidden: true));
    }
  }

  Future<void> clear() async {
    final uploads = await get();
    for (final upload in uploads) {
      await delete(upload.id);
    }
  }
}
