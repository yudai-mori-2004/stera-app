import "package:drift/drift.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";
import "package:stera/src/services/db/schema/enums/upload_error_category.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/upload_service/retry/upload_retry_policy.dart";

/// Drives the upload session/part state machines (doc 03) off the normalized
/// DB, applying the retry taxonomy + budgets (doc 06 via [UploadRetryPolicy]).
///
/// This owns the **reliability transitions** — what happens when a part
/// completes or fails and when a whole session attempt fails. The byte
/// transfer (native window engine / HTTP) and the backend calls
/// (start/parts/complete) plug in *underneath* via the caller, which feeds
/// results into the `record*` methods here. Every method is a small, idempotent
/// DB transition, safe to replay after a crash.
class UploadOrchestrator {
  UploadOrchestrator({
    UploadSessionDb? sessionDb,
    UploadRetryPolicy? retryPolicy,
    DateTime Function()? now,
  }) : _db = sessionDb ?? UploadSessionDb.instance,
       _policy = retryPolicy ?? UploadRetryPolicy(),
       _now = now ?? DateTime.now;

  final UploadSessionDb _db;
  final UploadRetryPolicy _policy;
  final DateTime Function() _now;

  AppDatabase get _raw => _db.db;

  /// A part finished uploading. Marks it `uploaded`, resets the session's
  /// no-progress budget (progress *was* made — doc 06 §2), and promotes the
  /// session to `finalizing` once every part is uploaded.
  Future<SessionState> recordPartCompleted(
    String sessionId,
    int partNumber, {
    required String etag,
    String? md5,
  }) async {
    await _db.markPartUploaded(sessionId, partNumber, etag: etag, md5: md5);
    await _resetNoProgressCounter(sessionId);

    final counts = await _db.partCounts(sessionId);
    if (counts.total > 0 && counts.uploaded == counts.total) {
      await _db.setSessionState(sessionId, SessionState.finalizing);
      return SessionState.finalizing;
    }
    return SessionState.transferring;
  }

  /// A part's upload attempt failed. Applies the per-part retry policy, updates
  /// the part row accordingly, and escalates to a terminal session failure if
  /// the part can no longer make progress.
  ///
  /// Tracks two counters (doc 06 §2): `attempts` (total, cap 15) and
  /// `attemptsAtUrl` (per current URL, cap 5 → then refresh, which resets it).
  /// `urlExpired` never consumes either budget.
  Future<PartRetryAction> recordPartFailed(
    String sessionId,
    int partNumber,
    UploadErrorCategory category,
  ) async {
    final part = await _getPart(sessionId, partNumber);
    if (part == null) return const PartRetryAction.giveUp();

    final counts = category.countsAgainstAttemptBudget;
    final newTotal = counts ? part.attempts + 1 : part.attempts;
    final newAtUrl = counts ? part.attemptsAtUrl + 1 : part.attemptsAtUrl;
    final action = _policy.forPart(
      category: category,
      attemptsAtUrl: newAtUrl,
      attemptsTotal: newTotal,
    );

    switch (action.kind) {
      case PartRetryKind.retry:
        // Same URL — keep both counters.
        await _db.updatePart(
          sessionId,
          partNumber,
          UploadPartsCompanion(
            state: const Value(PartState.urlReady),
            attempts: Value(newTotal),
            attemptsAtUrl: Value(newAtUrl),
            lastErrorCode: Value(category.name),
          ),
        );
      case PartRetryKind.refreshUrl:
        // Demote to planned, drop the stale URL (re-presigned), reset per-URL.
        await _db.updatePart(
          sessionId,
          partNumber,
          UploadPartsCompanion(
            state: const Value(PartState.planned),
            url: const Value(null),
            urlExpiresAt: const Value(null),
            attempts: Value(newTotal),
            attemptsAtUrl: const Value(0),
            lastErrorCode: Value(category.name),
          ),
        );
      case PartRetryKind.giveUp:
        await _db.updatePart(
          sessionId,
          partNumber,
          UploadPartsCompanion(
            attempts: Value(newTotal),
            attemptsAtUrl: Value(newAtUrl),
            lastErrorCode: Value(category.name),
          ),
        );
        await _db.markSessionFailed(
          sessionId,
          errorCode: category.name,
          errorDetail: "part $partNumber exhausted its retry budget",
        );
    }
    return action;
  }

  /// A whole transfer attempt for the session failed (no part made progress, or
  /// a session-level error such as throttling). Schedules backoff
  /// (`waitingRetry` + `nextAttemptAt`) or fails terminally once the
  /// no-progress budget is spent.
  Future<SessionRetryAction> recordSessionFailure(
    String sessionId,
    UploadErrorCategory category, {
    String? detail,
  }) async {
    final session = await _db.getSession(sessionId);
    if (session == null) return const SessionRetryAction.giveUp();

    if (!category.isRetryable) {
      await _db.markSessionFailed(
        sessionId,
        errorCode: category.name,
        errorDetail: detail,
      );
      return const SessionRetryAction.giveUp();
    }

    final attempts = session.attemptsWithoutProgress + 1;
    final action = _policy.forSession(attemptsWithoutProgress: attempts);

    switch (action.kind) {
      case SessionRetryKind.retry:
        await _db.markSessionWaitingRetry(
          sessionId,
          errorCode: category.name,
          errorDetail: detail,
          nextAttemptAt: _now().add(action.delay!),
          attemptsWithoutProgress: attempts,
        );
      case SessionRetryKind.giveUp:
        await _db.markSessionFailed(
          sessionId,
          errorCode: category.name,
          errorDetail: detail ?? "session retry budget exhausted",
        );
    }
    return action;
  }

  /// Manual retry of a terminally-failed session: `failedTerminal → queued`,
  /// **preserving all part rows and the multipart identity** (W7). Only the
  /// budget + error are reset; uploaded parts resume where they left off.
  Future<void> retrySession(String sessionId) =>
      (_raw.update(_raw.uploadSessions)..where((s) => s.id.equals(sessionId)))
          .write(
            UploadSessionsCompanion(
              state: const Value(SessionState.queued),
              attemptsWithoutProgress: const Value(0),
              lastErrorCode: const Value(null),
              lastErrorDetail: const Value(null),
              nextAttemptAt: const Value(null),
              updatedAt: Value(_now()),
            ),
          );

  /// Sessions whose scheduled backoff has elapsed and are ready to run again.
  Future<List<UploadSession>> dueForRetry() async {
    final now = _now();
    final waiting = await _db.getSessionsByStates([SessionState.waitingRetry]);
    return waiting
        .where((s) => s.nextAttemptAt == null || !s.nextAttemptAt!.isAfter(now))
        .toList();
  }

  /// Progress in `[0, 1]`, derived from uploaded part bytes (never a stored
  /// float — eliminates the drift bug class).
  Future<double> progressFor(String sessionId) async {
    final session = await _db.getSession(sessionId);
    if (session == null || session.fileSize <= 0) return 0;
    final bytes = await _db.uploadedBytes(sessionId);
    return (bytes / session.fileSize).clamp(0.0, 1.0);
  }

  Future<void> _resetNoProgressCounter(String sessionId) =>
      (_raw.update(_raw.uploadSessions)..where((s) => s.id.equals(sessionId)))
          .write(const UploadSessionsCompanion(
            attemptsWithoutProgress: Value(0),
          ));

  Future<UploadPart?> _getPart(String sessionId, int partNumber) =>
      (_raw.select(_raw.uploadParts)..where(
        (p) => p.sessionId.equals(sessionId) & p.partNumber.equals(partNumber),
      )).getSingleOrNull();
}
