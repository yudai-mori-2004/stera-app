import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:stera/src/services/db/schema/enums/upload_error_category.dart";
import "package:stera/src/services/upload_service/retry/upload_retry_policy.dart";

/// A Random that always returns [value]; with 0.5 the jitter multiplier is
/// exactly 1.0, so backoff delays are deterministic and exactly assertable.
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => (value * max).floor();
  @override
  bool nextBool() => value >= 0.5;
}

void main() {
  // 0.5 → no jitter (multiplier 1.0).
  UploadRetryPolicy noJitter() => UploadRetryPolicy(random: _FixedRandom(0.5));

  group("Backoff", () {
    final rng = _FixedRandom(0.5);
    const backoff = Backoff(base: Duration(seconds: 1), cap: Duration(seconds: 60));

    test("first retry is ~base, then doubles", () {
      expect(backoff.delayFor(1, rng), const Duration(seconds: 1));
      expect(backoff.delayFor(2, rng), const Duration(seconds: 2));
      expect(backoff.delayFor(4, rng), const Duration(seconds: 8));
    });

    test("is clamped to cap", () {
      // 2^9 = 512 s, well over the 60 s cap.
      expect(backoff.delayFor(10, rng), const Duration(seconds: 60));
    });

    test("jitter stays within ±fraction of the capped value", () {
      const b = Backoff(base: Duration(seconds: 10), cap: Duration(minutes: 5));
      for (final v in [0.0, 0.25, 0.75, 1.0]) {
        final d = b.delayFor(1, _FixedRandom(v));
        expect(d.inMilliseconds, greaterThanOrEqualTo(7500)); // 10s * 0.75
        expect(d.inMilliseconds, lessThanOrEqualTo(12500)); // 10s * 1.25
      }
    });
  });

  group("forPart", () {
    test("non-retryable category gives up", () {
      final a = noJitter().forPart(
        category: UploadErrorCategory.clientError,
        attemptsAtUrl: 1,
        attemptsTotal: 1,
      );
      expect(a.kind, PartRetryKind.giveUp);
    });

    test("urlExpired refreshes the URL without consuming the budget", () {
      final a = noJitter().forPart(
        category: UploadErrorCategory.urlExpired,
        attemptsAtUrl: 99,
        attemptsTotal: 99,
      );
      expect(a.kind, PartRetryKind.refreshUrl);
    });

    test("retries the same URL with backoff while under per-URL budget", () {
      final a = noJitter().forPart(
        category: UploadErrorCategory.network,
        attemptsAtUrl: 2,
        attemptsTotal: 2,
      );
      expect(a.kind, PartRetryKind.retry);
      expect(a.delay, const Duration(seconds: 2)); // 1s base * 2^(2-1)
    });

    test("refreshes URL once per-URL attempts are exhausted but budget remains", () {
      final a = noJitter().forPart(
        category: UploadErrorCategory.network,
        attemptsAtUrl: UploadRetryPolicy.partAttemptsPerUrl,
        attemptsTotal: 6,
      );
      expect(a.kind, PartRetryKind.refreshUrl);
    });

    test("gives up once the total per-part budget is exhausted", () {
      final a = noJitter().forPart(
        category: UploadErrorCategory.network,
        attemptsAtUrl: 1,
        attemptsTotal: UploadRetryPolicy.partAttemptsTotal,
      );
      expect(a.kind, PartRetryKind.giveUp);
    });
  });

  group("forSession", () {
    test("retries with 30s base backoff while under budget", () {
      final a = noJitter().forSession(attemptsWithoutProgress: 1);
      expect(a.kind, SessionRetryKind.retry);
      expect(a.delay, const Duration(seconds: 30));
    });

    test("gives up at the no-progress budget", () {
      final a = noJitter().forSession(
        attemptsWithoutProgress:
            UploadRetryPolicy.sessionAttemptsWithoutProgress,
      );
      expect(a.kind, SessionRetryKind.giveUp);
    });
  });

  group("forFinalization", () {
    test("retries up to the finalization budget", () {
      expect(
        noJitter().forFinalization(attempts: 1).kind,
        SessionRetryKind.retry,
      );
      expect(
        noJitter()
            .forFinalization(attempts: UploadRetryPolicy.finalizationAttempts)
            .kind,
        SessionRetryKind.giveUp,
      );
    });
  });
}
