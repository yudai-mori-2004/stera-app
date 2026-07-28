import "package:stera/src/services/db/upload_session_db.dart";

/// Produces a redacted snapshot of normalized upload state for support bundles
/// and diagnostic context (a background failure with no state snapshot is a report
/// we close as "cannot reproduce" — practice 08).
///
/// **Redaction is deliberate:** presigned URLs are credentials and are never
/// included (practice 08, "log the key/part number, never the URL"). The
/// snapshot carries states, counts, derived progress, and error *codes* only —
/// nothing that could grant upload access or leak a user identifier.
class UploadDiagnostics {
  UploadDiagnostics({UploadSessionDb? sessionDb})
    : _db = sessionDb ?? UploadSessionDb.instance;

  final UploadSessionDb _db;

  /// A JSON-safe snapshot: an aggregate state histogram plus a per-session
  /// summary. Safe to write to a support bundle.
  Future<Map<String, Object?>> snapshot() async {
    final sessions = await _db.getSessions();

    final byState = <String, int>{};
    final summaries = <Map<String, Object?>>[];

    for (final s in sessions) {
      byState[s.state.name] = (byState[s.state.name] ?? 0) + 1;

      final counts = await _db.partCounts(s.id);
      final bytes = await _db.uploadedBytes(s.id);

      summaries.add({
        "id": s.id,
        "state": s.state.name,
        "fileName": s.fileName,
        "fileSizeBytes": s.fileSize,
        "progress": s.fileSize > 0
            ? (bytes / s.fileSize).clamp(0.0, 1.0)
            : 0.0,
        "partsUploaded": counts.uploaded,
        "partsTotal": counts.total,
        "hasMultipartUpload": s.s3UploadId != null,
        "lastErrorCode": s.lastErrorCode,
        "attemptsWithoutProgress": s.attemptsWithoutProgress,
        "nextAttemptAt": s.nextAttemptAt?.toIso8601String(),
      });
    }

    return {
      "schema": "normalized-v1",
      "sessionCount": sessions.length,
      "byState": byState,
      "sessions": summaries,
    };
  }
}
