import "dart:math";

import "package:stera/src/services/db/schema/enums/upload_error_category.dart";

/// Exponential backoff with ±jitter.
///
/// `delayFor(priorAttempts)` returns `base * 2^(priorAttempts - 1)`, clamped to
/// `cap`, then multiplied by a jitter factor in `[1 - jitterFraction,
/// 1 + jitterFraction]`. `priorAttempts` is 1-based: the first retry (one prior
/// failure) gets ~`base`.
class Backoff {
  const Backoff({
    required this.base,
    required this.cap,
    this.jitterFraction = 0.25,
  });

  final Duration base;
  final Duration cap;
  final double jitterFraction;

  Duration delayFor(int priorAttempts, Random random) {
    final exponent = priorAttempts <= 1
        ? 0
        : (priorAttempts - 1 > 30 ? 30 : priorAttempts - 1);
    final rawMs = base.inMilliseconds * (1 << exponent);
    final cappedMs = rawMs > cap.inMilliseconds ? cap.inMilliseconds : rawMs;
    final jitter = 1 + (random.nextDouble() * 2 - 1) * jitterFraction;
    final ms = (cappedMs * jitter).round();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }
}

enum PartRetryKind {
  /// Retry the same URL after [PartRetryAction.delay].
  retry,

  /// Demote the part to `planned` and fetch a fresh presigned URL.
  refreshUrl,

  /// Stop — the part (and its session) cannot make progress.
  giveUp,
}

class PartRetryAction {
  const PartRetryAction._(this.kind, [this.delay]);
  const PartRetryAction.giveUp() : this._(PartRetryKind.giveUp);
  const PartRetryAction.refreshUrl() : this._(PartRetryKind.refreshUrl);
  const PartRetryAction.retryAfter(Duration delay)
    : this._(PartRetryKind.retry, delay);

  final PartRetryKind kind;
  final Duration? delay;
}

enum SessionRetryKind { retry, giveUp }

class SessionRetryAction {
  const SessionRetryAction._(this.kind, [this.delay]);
  const SessionRetryAction.giveUp() : this._(SessionRetryKind.giveUp);
  const SessionRetryAction.retryAfter(Duration delay)
    : this._(SessionRetryKind.retry, delay);

  final SessionRetryKind kind;
  final Duration? delay;
}

/// Retry budgets + backoff for the upload state machine. Three independent
/// budgets, each scoped to what it protects (06 §2):
///
///   - **part attempt** (one PUT): 5 per URL, 15 total per part
///   - **session attempt**: 5 *without progress* (any newly uploaded part
///     resets the counter, so a flaky multi-hour upload isn't killed at 3)
///   - **finalization**: 8
class UploadRetryPolicy {
  UploadRetryPolicy({Random? random}) : _random = random ?? Random();

  final Random _random;

  static const int partAttemptsPerUrl = 5;
  static const int partAttemptsTotal = 15;
  static const int sessionAttemptsWithoutProgress = 5;
  static const int finalizationAttempts = 8;

  static const Backoff partBackoff = Backoff(
    base: Duration(seconds: 1),
    cap: Duration(seconds: 60),
  );
  static const Backoff sessionBackoff = Backoff(
    base: Duration(seconds: 30),
    cap: Duration(minutes: 30),
  );
  static const Backoff finalizationBackoff = Backoff(
    base: Duration(seconds: 10),
    cap: Duration(hours: 1),
  );

  /// What to do with a part that just failed.
  ///
  /// - non-retryable category → give up
  /// - `urlExpired` → refresh URL (does not consume the attempt budget)
  /// - total-attempt budget exhausted → give up
  /// - current URL's attempts exhausted (but budget remains) → refresh URL
  /// - otherwise → retry the same URL after backoff
  PartRetryAction forPart({
    required UploadErrorCategory category,
    required int attemptsAtUrl,
    required int attemptsTotal,
  }) {
    if (!category.isRetryable) return const PartRetryAction.giveUp();

    if (category == UploadErrorCategory.urlExpired) {
      return const PartRetryAction.refreshUrl();
    }

    if (attemptsTotal >= partAttemptsTotal) {
      return const PartRetryAction.giveUp();
    }

    if (attemptsAtUrl >= partAttemptsPerUrl) {
      return const PartRetryAction.refreshUrl();
    }

    return PartRetryAction.retryAfter(
      partBackoff.delayFor(attemptsAtUrl, _random),
    );
  }

  /// Whether a session that failed *without making progress* should keep going.
  SessionRetryAction forSession({required int attemptsWithoutProgress}) {
    if (attemptsWithoutProgress >= sessionAttemptsWithoutProgress) {
      return const SessionRetryAction.giveUp();
    }
    return SessionRetryAction.retryAfter(
      sessionBackoff.delayFor(attemptsWithoutProgress, _random),
    );
  }

  /// Whether a failed `complete` / `/assets` finalization should be retried.
  SessionRetryAction forFinalization({required int attempts}) {
    if (attempts >= finalizationAttempts) {
      return const SessionRetryAction.giveUp();
    }
    return SessionRetryAction.retryAfter(
      finalizationBackoff.delayFor(attempts, _random),
    );
  }
}
