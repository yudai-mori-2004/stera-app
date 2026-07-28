import "package:drift/drift.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";

/// One row per file the user wants uploaded.
///
/// Replaces the legacy [Uploads] table's wholesale-rewritten JSON columns
/// (`partUrls`, `uploadedParts`) with a normalized session + per-part model
/// ([UploadParts]). Runs alongside [Uploads] during the Phase 1 dual-read
/// window.
@DataClassName("UploadSession")
class UploadSessions extends Table {
  /// uuid; doubles as the `clientUploadId` sent to the backend for /start
  /// idempotency.
  TextColumn get id => text()();

  TextColumn get filepath => text()();
  IntColumn get fileSize => integer()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get metadataFilepath => text().nullable()();

  // Chunk plan — frozen at `preparing`; uniform part size (R2 requirement).
  IntColumn get chunkSize => integer().nullable()();
  IntColumn get partCount => integer().nullable()();

  // Server identity — persisted once multipart start succeeds.
  TextColumn get s3Key => text().nullable()();
  TextColumn get s3UploadId => text().nullable()();
  TextColumn get assetId => text().nullable()();

  // State machine (doc 03).
  TextColumn get state => textEnum<SessionState>().withDefault(
    Constant(SessionState.queued.name),
  )();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorDetail => text().nullable()();
  IntColumn get attemptsWithoutProgress =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  // Integrity & dedup (doc 06 §4).
  TextColumn get fingerprint => text().nullable()();
  DateTimeColumn get sourceMtime => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  // Recording task linkage, carried over from the legacy schema.
  TextColumn get taskId => text().nullable()();
  TextColumn get subtaskId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
