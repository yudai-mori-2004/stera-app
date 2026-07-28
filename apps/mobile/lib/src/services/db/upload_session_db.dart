import "package:drift/drift.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/part_state.dart";
import "package:stera/src/services/db/schema/enums/session_state.dart";

/// Data access for the normalized upload schema (`upload_sessions` +
/// `upload_parts`).
///
/// Runs alongside the legacy [UploadDb] during the Phase 1 dual-read window.
/// Every mutation writes only the columns it owns (never a full row) so
/// concurrent part/state writes can't clobber each other — the bug class the
/// normalized schema exists to remove.
class UploadSessionDb {
  UploadSessionDb(this.db);

  /// Production singleton bound to the app database. Tests construct
  /// `UploadSessionDb(AppDatabase.forTesting(...))` against an in-memory DB.
  static final UploadSessionDb instance = UploadSessionDb(AppDatabase.instance);

  final AppDatabase db;

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  Stream<List<UploadSession>> watchSessions() =>
      db.select(db.uploadSessions).watch();

  Future<List<UploadSession>> getSessions() =>
      db.select(db.uploadSessions).get();

  Future<UploadSession?> getSession(String id) => (db.select(
    db.uploadSessions,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<UploadSession>> getSessionsByStates(
    List<SessionState> states,
  ) => (db.select(db.uploadSessions)
        ..where((s) => s.state.isIn(states.map((e) => e.name).toList()))
        ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
      .get();

  Future<void> insertSession(UploadSessionsCompanion session) =>
      db.into(db.uploadSessions).insert(session);

  /// Writes only the state column (+ `updatedAt`). Use for plain transitions
  /// that carry no error/backoff (e.g. `transferring → finalizing`).
  Future<void> setSessionState(String id, SessionState state) =>
      (db.update(db.uploadSessions)..where((s) => s.id.equals(id))).write(
        UploadSessionsCompanion(
          state: Value(state),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Records a retryable failure: `state = waitingRetry` plus the error and the
  /// scheduled backoff. `attemptsWithoutProgress` is the *updated* count the
  /// caller computed (any newly uploaded part resets it to 0 — see 06 §2).
  Future<void> markSessionWaitingRetry(
    String id, {
    required String errorCode,
    String? errorDetail,
    required DateTime nextAttemptAt,
    required int attemptsWithoutProgress,
  }) => (db.update(db.uploadSessions)..where((s) => s.id.equals(id))).write(
    UploadSessionsCompanion(
      state: const Value(SessionState.waitingRetry),
      lastErrorCode: Value(errorCode),
      lastErrorDetail: Value(errorDetail),
      nextAttemptAt: Value(nextAttemptAt),
      attemptsWithoutProgress: Value(attemptsWithoutProgress),
      updatedAt: Value(DateTime.now()),
    ),
  );

  /// Records a terminal failure with its diagnostic cause.
  Future<void> markSessionFailed(
    String id, {
    required String errorCode,
    String? errorDetail,
  }) => (db.update(db.uploadSessions)..where((s) => s.id.equals(id))).write(
    UploadSessionsCompanion(
      state: const Value(SessionState.failedTerminal),
      lastErrorCode: Value(errorCode),
      lastErrorDetail: Value(errorDetail),
      updatedAt: Value(DateTime.now()),
    ),
  );

  /// Re-arms a session for a **manual retry**. Without this a failed windowed
  /// upload can never resume: the legacy row is reset to `pending`, but the
  /// windowed session stays `failedTerminal`, so the coordinator's
  /// `startSession` short-circuits on the terminal-state guard and returns a
  /// failure *instantly* — producing a tight retry→instant-fail→retry loop.
  ///
  /// Resets the session back to `queued` with a fresh no-progress budget and
  /// clears its error/backoff, and resets every **not-yet-`uploaded`** part to
  /// `planned` with fresh attempt counters and a dropped (stale) URL — so the
  /// part that exhausted its retry budget gets a clean slate. Already-`uploaded`
  /// parts are preserved, so the retry resumes from where it left off rather
  /// than restarting at 0%. No-op when the session doesn't exist.
  Future<void> resetForRetry(String sessionId) async {
    if (await getSession(sessionId) == null) return;
    await db.transaction(() async {
      await (db.update(db.uploadSessions)
            ..where((s) => s.id.equals(sessionId)))
          .write(
            UploadSessionsCompanion(
              state: const Value(SessionState.queued),
              attemptsWithoutProgress: const Value(0),
              lastErrorCode: const Value(null),
              lastErrorDetail: const Value(null),
              nextAttemptAt: const Value(null),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await (db.update(db.uploadParts)..where(
            (p) =>
                p.sessionId.equals(sessionId) &
                p.state.equals(PartState.uploaded.name).not(),
          )).write(
        UploadPartsCompanion(
          state: const Value(PartState.planned),
          attempts: const Value(0),
          attemptsAtUrl: const Value(0),
          url: const Value(null),
          urlExpiresAt: const Value(null),
          lastErrorCode: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Reset **every** part of a session to `planned` with cleared URL/ETag/MD5
  /// and zeroed attempt counters. Used when the multipart upload is replaced on
  /// restart (the prior upload is gone): everything the old upload held — part
  /// URLs and uploaded ETags alike — is invalid against the new uploadId, so the
  /// whole file must be re-presigned and re-sent.
  Future<void> resetAllPartsForRestart(String sessionId) =>
      (db.update(db.uploadParts)..where((p) => p.sessionId.equals(sessionId)))
          .write(
            UploadPartsCompanion(
              state: const Value(PartState.planned),
              url: const Value(null),
              urlExpiresAt: const Value(null),
              etag: const Value(null),
              md5: const Value(null),
              attempts: const Value(0),
              attemptsAtUrl: const Value(0),
              lastErrorCode: const Value(null),
              updatedAt: Value(DateTime.now()),
            ),
          );

  /// Persists the frozen chunk plan + server identity once `registering`
  /// succeeds. Only the provided columns are written.
  Future<void> setServerIdentity(
    String id, {
    String? s3Key,
    String? s3UploadId,
    String? assetId,
    int? chunkSize,
    int? partCount,
  }) => (db.update(db.uploadSessions)..where((s) => s.id.equals(id))).write(
    UploadSessionsCompanion(
      s3Key: s3Key == null ? const Value.absent() : Value(s3Key),
      s3UploadId: s3UploadId == null ? const Value.absent() : Value(s3UploadId),
      assetId: assetId == null ? const Value.absent() : Value(assetId),
      chunkSize: chunkSize == null ? const Value.absent() : Value(chunkSize),
      partCount: partCount == null ? const Value.absent() : Value(partCount),
      updatedAt: Value(DateTime.now()),
    ),
  );

  /// Deletes a session and its parts. Explicit (not relying on FK cascade,
  /// which only fires when `PRAGMA foreign_keys=ON`).
  Future<void> deleteSession(String id) async {
    await (db.delete(
      db.uploadParts,
    )..where((p) => p.sessionId.equals(id))).go();
    await (db.delete(db.uploadSessions)..where((s) => s.id.equals(id))).go();
  }

  /// Deletes sessions (and their parts) that have reached a terminal state —
  /// the windowed-engine equivalent of `UploadDb.deleteCompletedUploads`. Run
  /// at startup so finished/cancelled rows don't accumulate.
  Future<void> deleteTerminalSessions() async {
    final terminal = await getSessionsByStates([
      SessionState.completed,
      SessionState.cancelled,
    ]);
    for (final session in terminal) {
      await deleteSession(session.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Parts
  // ---------------------------------------------------------------------------

  Future<void> insertParts(List<UploadPartsCompanion> parts) =>
      db.batch((b) => b.insertAll(db.uploadParts, parts));

  Future<List<UploadPart>> getParts(String sessionId) =>
      (db.select(db.uploadParts)
            ..where((p) => p.sessionId.equals(sessionId))
            ..orderBy([(p) => OrderingTerm.asc(p.partNumber)]))
          .get();

  /// Parts still needing transfer (anything not `uploaded`).
  Future<List<UploadPart>> getPendingParts(String sessionId) =>
      (db.select(db.uploadParts)
            ..where(
              (p) =>
                  p.sessionId.equals(sessionId) &
                  p.state.equals(PartState.uploaded.name).not(),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.partNumber)]))
          .get();

  /// Writes only the supplied columns on one part (+ `updatedAt`).
  Future<void> updatePart(
    String sessionId,
    int partNumber,
    UploadPartsCompanion data,
  ) => (db.update(db.uploadParts)..where(
    (p) => p.sessionId.equals(sessionId) & p.partNumber.equals(partNumber),
  )).write(data.copyWith(updatedAt: Value(DateTime.now())));

  /// Marks a part `uploaded` with its result ETag + local MD5 — the cheap,
  /// per-part write that replaces the legacy 5-chunk JSON batch flush.
  Future<void> markPartUploaded(
    String sessionId,
    int partNumber, {
    required String etag,
    String? md5,
  }) => updatePart(
    sessionId,
    partNumber,
    UploadPartsCompanion(
      state: const Value(PartState.uploaded),
      etag: Value(etag),
      md5: md5 == null ? const Value.absent() : Value(md5),
    ),
  );

  // ---------------------------------------------------------------------------
  // Derived progress (never stored — eliminates the float-drift bug class)
  // ---------------------------------------------------------------------------

  /// Bytes uploaded so far = sum of `length` over `uploaded` parts. Part rows
  /// are ≤ ~640 even for 40 GB, so a Dart-side fold is trivial and avoids
  /// fragile aggregate SQL.
  Future<int> uploadedBytes(String sessionId) async {
    final parts = await getParts(sessionId);
    return parts
        .where((p) => p.state == PartState.uploaded)
        .fold<int>(0, (sum, p) => sum + p.length);
  }

  /// `(uploaded, total)` part counts for a session.
  Future<({int uploaded, int total})> partCounts(String sessionId) async {
    final parts = await getParts(sessionId);
    final uploaded = parts.where((p) => p.state == PartState.uploaded).length;
    return (uploaded: uploaded, total: parts.length);
  }
}
