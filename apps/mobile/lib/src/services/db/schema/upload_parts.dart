import "package:drift/drift.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/upload_sessions.dart";

/// One row per part of a multipart upload (~640 rows for a 40 GB file — trivial
/// for SQLite). A per-part completion is a ~200 B row update instead of
/// rewriting a growing JSON array, which is what made the legacy schema's
/// progress writes O(n²).
///
/// Drift generates the row class `UploadPart` (plural table → singular row, per
/// the naming convention); distinct from the legacy `UploadedPart` JSON model
/// the dual-read path still uses.
class UploadParts extends Table {
  TextColumn get sessionId =>
      text().references(UploadSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get partNumber => integer()(); // 1-based (S3 convention)
  IntColumn get offset => integer()();
  IntColumn get length => integer()();
  TextColumn get state => textEnum<PartState>().withDefault(
    Constant(PartState.planned.name),
  )();
  TextColumn get url => text().nullable()();
  DateTimeColumn get urlExpiresAt => dateTime().nullable()();
  TextColumn get etag => text().nullable()();
  TextColumn get md5 => text().nullable()();

  /// Total attempts across all URLs for this part (budget cap, doc 06 §2).
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Attempts against the *current* presigned URL; reset to 0 when a fresh URL
  /// is assigned. Lets the per-URL budget (5) stay distinct from the total (15).
  IntColumn get attemptsAtUrl => integer().withDefault(const Constant(0))();

  TextColumn get lastErrorCode => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sessionId, partNumber};
}
