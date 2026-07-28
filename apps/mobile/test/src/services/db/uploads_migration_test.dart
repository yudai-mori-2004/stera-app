import "dart:io";

import "package:drift/native.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqlite3/sqlite3.dart" as sqlite;
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";

/// Regression tests for [AppDatabase]'s `onUpgrade` migration.
///
/// A stale upgrader whose `uploads` table predates columns the current
/// migration referenced used to throw `no such column`, which left the
/// database unopenable. Because the upload list flips its loading spinner off
/// only on the first `db.watch()` emission, that surfaced as an infinite
/// `CupertinoActivityIndicator` with the user's recordings invisible. These
/// tests pin the migration's resilience to missing legacy columns.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp("uploads_migration_test");
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Seeds a sqlite file with a deliberately old `uploads` table (a subset of
  /// the current columns) at [userVersion], inserts [rowFilepath], and closes.
  File seedOldDatabase({
    required int userVersion,
    required String rowFilepath,
    required List<String> columnDefs,
    required Map<String, Object?> row,
  }) {
    final file = File("${tempDir.path}/stera.sqlite");
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      "CREATE TABLE uploads (${columnDefs.join(", ")})",
    );
    final cols = row.keys.toList();
    final placeholders = List.filled(cols.length, "?").join(", ");
    raw.execute(
      "INSERT INTO uploads (${cols.join(", ")}) VALUES ($placeholders)",
      row.values.toList(),
    );
    raw.execute("PRAGMA user_version = $userVersion");
    raw.close();
    return file;
  }

  test(
    "upgrades a pre-v7 uploads table missing newer columns without throwing",
    () async {
      // An old schema that lacks is_hidden, parts_count, uploaded_parts,
      // part_urls, task/subtask columns, metadata_filepath, etc.
      final file = seedOldDatabase(
        userVersion: 6,
        rowFilepath: "documents://old_clip.mp4",
        columnDefs: const [
          "id INTEGER PRIMARY KEY AUTOINCREMENT",
          "filepath TEXT NOT NULL",
          "filesize INTEGER",
          "duration_ms INTEGER",
          "thumnbnail TEXT",
          "status TEXT",
          "file_name TEXT",
          "mime_type TEXT",
          "progress REAL",
          "retry_count INTEGER",
          "s3_presign_response TEXT",
          "multipart_start_response TEXT",
          "created_at INTEGER",
          "updated_at INTEGER",
        ],
        row: {
          "filepath": "documents://old_clip.mp4",
          "filesize": 1234,
          "status": UploadStatus.notStarted.name,
          "file_name": "old_clip.mp4",
          "mime_type": "video/mp4",
          "retry_count": 0,
          "created_at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
          "updated_at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
      );

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      // The first query forces the migration to run. It must not throw.
      final rows = await db.select(db.uploads).get();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.filepath, "documents://old_clip.mp4");
      expect(row.fileName, "old_clip.mp4");
      expect(row.status, UploadStatus.notStarted);
      // Columns absent from the old table fall back to their new defaults.
      expect(row.isHidden, isFalse);
      expect(row.partsCount, isNull);
      expect(row.taskId, isNull);
      expect(row.metadataFilepath, isNull);
    },
  );

  test("remaps legacy task/subtask string columns on a pre-v7 upgrade", () async {
    final file = seedOldDatabase(
      userVersion: 6,
      rowFilepath: "documents://tasked.mp4",
      columnDefs: const [
        "id INTEGER PRIMARY KEY AUTOINCREMENT",
        "filepath TEXT NOT NULL",
        "filesize INTEGER",
        "status TEXT",
        "file_name TEXT",
        "mime_type TEXT",
        "retry_count INTEGER",
        "created_at INTEGER",
        "updated_at INTEGER",
        "task_id_str TEXT",
        "subtask_id TEXT",
        "task_name TEXT",
      ],
      row: {
        "filepath": "documents://tasked.mp4",
        "filesize": 10,
        "status": UploadStatus.notStarted.name,
        "file_name": "tasked.mp4",
        "mime_type": "video/mp4",
        "retry_count": 0,
        "created_at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "updated_at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "task_id_str": "task-123",
        "subtask_id": "sub-456",
        "task_name": "My Task",
      },
    );

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final row = (await db.select(db.uploads).get()).single;
    expect(row.taskId, "task-123");
    expect(row.subtaskId, "sub-456");
    expect(row.taskName, "My Task");
  });
}
