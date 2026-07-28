import "package:drift/drift.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:stera/src/services/upload_service/data/repo/upload_repo.dart";

/// Fetches presigned part URLs. A function seam over the static [UploadRepo]
/// (practice 04) so the manager is testable with a fake.
typedef PartUrlFetcher =
    Future<(MultipartPartsResponse?, Failure?)> Function({
      required String key,
      required String uploadId,
      int? partCount,
      List<int>? partNumbers,
    });

/// Keeps a session's not-yet-uploaded parts supplied with **fresh** presigned
/// URLs, fetched just-in-time in bounded batches and persisted to the part rows.
///
/// A presigned URL outlives neither a multi-hour upload nor the ~1 h–1 day TTL,
/// so holding all of them up front goes stale (the bug the windowed redesign
/// removes). Instead this fetches a batch only for parts that need one, and
/// refreshes a URL before it expires (default T-10 min) while the app is alive.
class PresignManager {
  PresignManager({
    UploadSessionDb? sessionDb,
    PartUrlFetcher? fetchUrls,
    Duration refreshLeadTime = const Duration(minutes: 10),
    int batchSize = 256,
    DateTime Function()? now,
  }) : _db = sessionDb ?? UploadSessionDb.instance,
       _fetch = fetchUrls ?? UploadRepo.getMultipartPartUrls,
       _refreshLeadTime = refreshLeadTime,
       _batchSize = batchSize,
       _now = now ?? DateTime.now;

  final UploadSessionDb _db;
  final PartUrlFetcher _fetch;
  final Duration _refreshLeadTime;
  final int _batchSize;
  final DateTime Function() _now;

  /// Part numbers that need a (fresh) URL: not yet uploaded, and either lacking
  /// a URL (`planned`) or holding one that expires within the refresh lead time.
  List<int> partsNeedingUrls(List<UploadPart> parts) {
    final cutoff = _now().add(_refreshLeadTime);
    return parts
        .where((p) => p.state != PartState.uploaded)
        .where(
          (p) =>
              p.url == null ||
              p.urlExpiresAt == null ||
              !p.urlExpiresAt!.isAfter(cutoff),
        )
        .map((p) => p.partNumber)
        .toList();
  }

  /// Ensures up to [batchSize] of the parts that need URLs get fresh ones, in a
  /// single round-trip, persisted to their rows (`→ urlReady`). Returns the
  /// number of parts assigned a fresh URL, or a [Failure].
  Future<(int, Failure?)> ensureUrls(String sessionId) async {
    final session = await _db.getSession(sessionId);
    if (session == null) {
      return (0, Failure(message: "No such session", code: ErrorType.notFound));
    }

    final key = session.s3Key;
    final uploadId = session.s3UploadId;
    if (key == null || uploadId == null) {
      return (
        0,
        Failure(
          message: "Session not registered; cannot presign yet",
          code: ErrorType.badRequest,
        ),
      );
    }

    final parts = await _db.getParts(sessionId);
    final needing = partsNeedingUrls(parts);
    if (needing.isEmpty) return (0, null);

    final batch = needing.take(_batchSize).toList();
    final (resp, err) = await _fetch(
      key: key,
      uploadId: uploadId,
      partNumbers: batch,
    );
    if (err != null) return (0, err);
    if (resp == null) {
      return (
        0,
        Failure(message: "Empty presign response", code: ErrorType.unknown),
      );
    }

    var assigned = 0;
    for (final partUrl in resp.urls) {
      await _db.updatePart(
        sessionId,
        partUrl.partNumber,
        UploadPartsCompanion(
          url: Value(partUrl.url),
          urlExpiresAt: Value(partUrl.expiresAt),
          state: const Value(PartState.urlReady),
        ),
      );
      assigned++;
    }
    return (assigned, null);
  }
}
