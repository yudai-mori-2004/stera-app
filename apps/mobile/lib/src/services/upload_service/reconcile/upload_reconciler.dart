import "package:drift/drift.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/data/models/list_parts_response.dart";
import "package:stera/src/services/upload_service/data/repo/upload_repo.dart";

/// Fetches storage's part list. A function seam (rather than converting the
/// static [UploadRepo] to an instance) so the reconciler is testable with a
/// fake — the cheapest injection per practice 04, default to the real repo.
typedef ListPartsFetcher =
    Future<(ListPartsResponse?, Failure?)> Function({
      required String key,
      required String uploadId,
    });

enum ReconcileOutcome {
  /// Local part rows were diffed against storage and brought into agreement.
  reconciled,

  /// Storage already holds the finished object (server auto-completed or the
  /// multipart was completed before we persisted it) → finalize, don't re-upload.
  completedByServer,

  /// The multipart upload is gone and no object exists → the session must
  /// restart from registering.
  restartRequired,

  /// Nothing to reconcile (no server identity yet, or session missing).
  skipped,

  /// The ListParts call failed; caller should retry later.
  failed,
}

class ReconcileResult {
  const ReconcileResult(this.outcome, {this.adopted = 0, this.demoted = 0});
  final ReconcileOutcome outcome;
  final int adopted;
  final int demoted;
}

/// Reconciles a session's local part rows against what storage actually has
/// (`ListParts`). This is what makes resume self-healing: local journal loss,
/// a force-quit-lost window, or a server-side completion all converge to the
/// truth instead of re-uploading everything or finalizing a torn object.
class UploadReconciler {
  UploadReconciler({UploadSessionDb? sessionDb, ListPartsFetcher? fetchParts})
    : _db = sessionDb ?? UploadSessionDb.instance,
      _fetch = fetchParts ?? UploadRepo.listMultipartParts;

  final UploadSessionDb _db;
  final ListPartsFetcher _fetch;

  Future<ReconcileResult> reconcile(String sessionId) async {
    final session = await _db.getSession(sessionId);
    if (session == null) return const ReconcileResult(ReconcileOutcome.skipped);

    final key = session.s3Key;
    final uploadId = session.s3UploadId;
    if (key == null || uploadId == null) {
      // Pre-registration: there is no server upload to anchor against.
      return const ReconcileResult(ReconcileOutcome.skipped);
    }

    final (resp, err) = await _fetch(key: key, uploadId: uploadId);
    if (err != null || resp == null) {
      return const ReconcileResult(ReconcileOutcome.failed);
    }

    if (!resp.uploadExists) {
      if (resp.objectExists) {
        await _db.setSessionState(sessionId, SessionState.registeringAsset);
        return const ReconcileResult(ReconcileOutcome.completedByServer);
      }
      await _db.setSessionState(sessionId, SessionState.registering);
      return const ReconcileResult(ReconcileOutcome.restartRequired);
    }

    final localParts = await _db.getParts(sessionId);
    final serverByNumber = {for (final p in resp.parts) p.partNumber: p};

    var adopted = 0;
    var demoted = 0;

    for (final local in localParts) {
      final server = serverByNumber[local.partNumber];

      if (server == null) {
        // Local thinks it's done but storage has no such part → re-upload.
        if (local.state == PartState.uploaded) {
          await _demote(sessionId, local.partNumber);
          demoted++;
        }
        continue;
      }

      if (local.state != PartState.uploaded) {
        // Storage has it; adopt the server ETag as truth.
        await _adopt(sessionId, local.partNumber, server.etag);
        adopted++;
      } else if (local.etag != server.etag) {
        // Both claim done but the ETags disagree → re-upload (last write wins).
        await _demote(sessionId, local.partNumber);
        demoted++;
      }
    }

    return ReconcileResult(
      ReconcileOutcome.reconciled,
      adopted: adopted,
      demoted: demoted,
    );
  }

  Future<void> _adopt(String sessionId, int partNumber, String etag) =>
      _db.updatePart(
        sessionId,
        partNumber,
        UploadPartsCompanion(
          state: const Value(PartState.uploaded),
          etag: Value(etag),
        ),
      );

  Future<void> _demote(String sessionId, int partNumber) => _db.updatePart(
    sessionId,
    partNumber,
    const UploadPartsCompanion(
      state: Value(PartState.planned),
      etag: Value(null),
      url: Value(null),
      urlExpiresAt: Value(null),
    ),
  );
}
