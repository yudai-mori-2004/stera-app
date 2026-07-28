/// Failure taxonomy for uploads. Every raw error (Dart or native) is mapped to
/// exactly one category at the point of detection, and the category — not the
/// raw error — drives retry policy.
enum UploadErrorCategory {
  /// Socket errors, DNS, connection reset, not-connected.
  network,

  /// Request idle timeout / stalled transfer.
  timeout,

  /// 403 with expiry signature, or a URL past its recorded expiry.
  urlExpired,

  /// 5xx from storage or backend.
  serverError,

  /// 429 / SlowDown.
  throttled,

  /// 4xx other than 401/403/429.
  clientError,

  /// Source missing/unreadable, short read, protected-data (pre-unlock).
  fileError,

  /// Temp extraction failed for lack of space.
  diskFull,

  /// Backend 401 (app auth, not a presign issue).
  authError;

  /// Whether a failure in this category is worth retrying.
  ///
  /// `fileError` is *conditionally* retryable (reboot-before-unlock resolves on
  /// next unlock); the orchestrator special-cases that. The base policy here
  /// treats it as non-retryable so a genuinely deleted file fails fast.
  bool get isRetryable => switch (this) {
    UploadErrorCategory.network => true,
    UploadErrorCategory.timeout => true,
    UploadErrorCategory.urlExpired => true,
    UploadErrorCategory.serverError => true,
    UploadErrorCategory.throttled => true,
    UploadErrorCategory.authError => true,
    UploadErrorCategory.diskFull => true,
    UploadErrorCategory.clientError => false,
    UploadErrorCategory.fileError => false,
  };

  /// `urlExpired` demotes the part and re-presigns rather than counting as a
  /// failed attempt, so it must not consume the per-part attempt budget. See
  /// 06 §1–2.
  bool get countsAgainstAttemptBudget => this != UploadErrorCategory.urlExpired;

  /// Throttling backs off the whole session (pause refill) rather than one
  /// part. See 06 §1.
  bool get isSessionLevel => this == UploadErrorCategory.throttled;
}
