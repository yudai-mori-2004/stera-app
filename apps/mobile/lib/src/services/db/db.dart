import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/schema/models/multipart_start_response_type_converter.dart";
import "package:stera/src/services/db/schema/models/part_url_type_converter.dart";
import "package:stera/src/services/db/schema/models/s3_presign_response_type_converter.dart";
import "package:stera/src/services/db/schema/models/upload_part.dart";
import "package:stera/src/services/db/schema/upload_parts.dart";
import "package:stera/src/services/db/schema/upload_sessions.dart";
import "package:stera/src/services/db/schema/uploads.dart";
import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";
import "package:stera/src/services/upload_service/data/models/s3_presign_response.dart";
import "package:drift/drift.dart";
import "package:drift_flutter/drift_flutter.dart";
import "package:path_provider/path_provider.dart";

part "db.g.dart";

@DriftDatabase(tables: [Uploads, UploadSessions, UploadParts])
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal([QueryExecutor? executor])
    : super(executor ?? _openConnection());

  /// Test-only: builds an instance on a caller-supplied executor (e.g. an
  /// in-memory `NativeDatabase.memory()`), bypassing the singleton.
  AppDatabase.forTesting(super.executor);

  static AppDatabase? _instance;

  static AppDatabase get instance {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  static Future<void> init() async {
    _instance ??= AppDatabase._internal();
  }

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      /// Column names currently present on [table].
      Future<Set<String>> columnsOf(String table) async => (await customSelect(
        "PRAGMA table_info($table)",
      ).get()).map((row) => row.data["name"] as String).toSet();

      /// Rebuilds `uploads` from a renamed `uploads_old`, copying only the
      /// columns that exist on BOTH tables. Columns absent from the old table
      /// fall back to the new table's defaults/NULL, so an upgrade from any
      /// older schema can never fail on a missing column (a stale upgrader
      /// otherwise left the database unopenable, which hung the upload list
      /// on an infinite loading spinner).
      ///
      /// [overrides] maps a target column to a SQL expression evaluated
      /// against `uploads_old` — used to remap legacy task/subtask columns.
      Future<void> rebuildUploadsFromOld({
        Map<String, String> overrides = const {},
      }) async {
        final oldCols = await columnsOf("uploads_old");
        final newCols = await columnsOf("uploads");

        final insertCols = <String>[];
        final selectExprs = <String>[];
        for (final col in newCols) {
          if (overrides.containsKey(col)) {
            insertCols.add(col);
            selectExprs.add("${overrides[col]} AS $col");
          } else if (oldCols.contains(col)) {
            insertCols.add(col);
            selectExprs.add(col);
          }
          // Otherwise omit: the new table's default/NULL applies.
        }

        await customStatement(
          "INSERT INTO uploads (${insertCols.join(", ")}) "
          "SELECT ${selectExprs.join(", ")} FROM uploads_old",
        );
      }

      /// Adds [column] to [table] only when it isn't already present. A
      /// preceding `createTable` (run by an earlier `from < N` block on the
      /// same upgrade) builds the *current* full schema, so a later
      /// `addColumn` for a column that schema already has would otherwise throw
      /// "duplicate column name" and abort the whole migration.
      Future<void> addColumnIfMissing(
        TableInfo<Table, dynamic> table,
        GeneratedColumn<Object> column,
      ) async {
        final cols = await columnsOf(table.actualTableName);
        if (cols.contains(column.name)) return;
        await migrator.addColumn(table, column);
      }

      if (from < 7) {
        final existingColumns = await columnsOf("uploads");

        Future<void> addLegacyColumnIfMissing(String name, String type) async {
          if (existingColumns.contains(name)) return;
          await customStatement("ALTER TABLE uploads ADD COLUMN $name $type");
          existingColumns.add(name);
        }

        // Ensure the legacy task/subtask columns referenced by the remap
        // expressions below exist before we read from them.
        await addLegacyColumnIfMissing("task_id", "TEXT");
        await addLegacyColumnIfMissing("task_name", "TEXT");
        await addLegacyColumnIfMissing("task_id_str", "TEXT");
        await addLegacyColumnIfMissing("subtask_id", "TEXT");
        await addLegacyColumnIfMissing("subtask_id_str", "TEXT");
        await addLegacyColumnIfMissing("subtask_name", "TEXT");

        await customStatement("DROP TABLE IF EXISTS uploads_old");
        await customStatement("ALTER TABLE uploads RENAME TO uploads_old");
        await migrator.createTable(uploads);
        await rebuildUploadsFromOld(
          overrides: {
            "task_id":
                "NULLIF(COALESCE(NULLIF(task_id_str, ''), NULLIF(CAST(task_id AS TEXT), '0')), '')",
            "task_name": "NULLIF(task_name, '')",
            "subtask_id":
                "NULLIF(COALESCE(NULLIF(subtask_id, ''), NULLIF(subtask_id_str, '')), '')",
          },
        );
        await customStatement("DROP TABLE uploads_old");
      }

      if (from < 8) {
        await customStatement("DROP TABLE IF EXISTS uploads_old");
        await customStatement("ALTER TABLE uploads RENAME TO uploads_old");
        await migrator.createTable(uploads);
        await rebuildUploadsFromOld();
        await customStatement("DROP TABLE uploads_old");
      }

      if (from < 9) {
        // Remove spatial columns (spatialDataFilepath, spatialMultipartStartResponse,
        // spatialPartUrls, spatialUploadedParts, spatialPartsCount): they are
        // simply not copied since they no longer exist on the new table.
        await customStatement("DROP TABLE IF EXISTS uploads_old");
        await customStatement("ALTER TABLE uploads RENAME TO uploads_old");
        await migrator.createTable(uploads);
        await rebuildUploadsFromOld();
        await customStatement("DROP TABLE uploads_old");
      }

      if (from < 10) {
        await addColumnIfMissing(uploads, uploads.metadataFilepath);
      }

      if (from < 11) {
        // Phase 1: normalized upload schema runs alongside the legacy `uploads`
        // table (dual-read). The legacy `uploadedParts` JSON is exploded into
        // part rows in a later increment; for now just create the tables so
        // fresh sessions can use them. Existing in-flight uploads stay on the
        // legacy path.
        await migrator.createTable(uploadSessions);
        await migrator.createTable(uploadParts);
      }

      if (from < 12) {
        // Per-URL attempt counter (distinct from total attempts) for the
        // windowed engine's retry budget (doc 06 §2).
        await addColumnIfMissing(uploadParts, uploadParts.attemptsAtUrl);
      }
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: "stera",
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
