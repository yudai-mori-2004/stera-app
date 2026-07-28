/// Lifecycle of one upload session (one file).
///
/// Replaces the overloaded [UploadStatus] (which conflated waiting,
/// transferring, finalizing, and the failure reason).
enum SessionState {
  /// Waiting for the scheduler.
  queued,

  /// Resolving path/size/mime; computing the (frozen) chunk plan + fingerprint.
  preparing,

  /// `POST /multipart/start` in flight (idempotent via the session id /
  /// clientUploadId).
  registering,

  /// Window manager active; parts moving.
  transferring,

  /// All parts uploaded; reconcile + `POST /multipart/complete`.
  finalizing,

  /// `POST /assets` registering the finished object.
  registeringAsset,

  /// Done; local file + rows cleaned up after a grace period.
  completed,

  /// User intent, not an error. In-flight tasks finish; no refill.
  paused,

  /// Retryable failure; a backoff timer is scheduled (`nextAttemptAt`).
  waitingRetry,

  /// Needs user action (file gone, auth revoked, budget exhausted).
  failedTerminal,

  /// User abandoned; multipart aborted server-side.
  cancelled;

  /// No further automatic progress — either done or needs the user.
  bool get isTerminal =>
      this == SessionState.completed ||
      this == SessionState.failedTerminal ||
      this == SessionState.cancelled;

  /// The scheduler may drive this session toward completion.
  bool get isActive =>
      this == SessionState.queued ||
      this == SessionState.preparing ||
      this == SessionState.registering ||
      this == SessionState.transferring ||
      this == SessionState.finalizing ||
      this == SessionState.registeringAsset ||
      this == SessionState.waitingRetry;
}
