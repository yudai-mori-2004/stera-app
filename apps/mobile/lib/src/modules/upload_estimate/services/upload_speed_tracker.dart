import "package:stera/src/services/kv_store/kv_store.dart";

/// Result of an upload time estimate.
class UploadTimeEstimate {
  /// Estimated wall-clock time to finish the upload at the assumed speed.
  final Duration duration;

  /// The upload speed (bytes/sec) used to compute [duration].
  final double bytesPerSecond;

  /// `true` when [bytesPerSecond] comes from the user's own measured
  /// upload history, `false` when it's a generic fallback assumption.
  final bool basedOnMeasuredSpeed;

  const UploadTimeEstimate({
    required this.duration,
    required this.bytesPerSecond,
    required this.basedOnMeasuredSpeed,
  });
}

/// Tracks the user's real-world upload throughput and uses it to estimate
/// how long a new upload will take.
///
/// Speed is learned from completed uploads (total file bytes / wall-clock
/// time) and smoothed with an exponential moving average so a single slow
/// or fast network moment doesn't dominate the estimate.
class UploadSpeedTracker {
  UploadSpeedTracker._();

  /// KvStore key holding the smoothed measured speed in bytes/sec.
  static const String _kSpeedKey = "upload_speed_bytes_per_sec";

  /// Weight given to the newest sample in the moving average.
  static const double _emaAlpha = 0.5;

  /// Ignore samples from tiny files — their wall-clock time is dominated by
  /// per-request overhead rather than throughput, so they're noisy.
  static const int _minBytesForSample = 5 * 1024 * 1024; // 5 MB

  /// Fallback assumptions used until we have a measured sample.
  /// Expressed as bytes/sec (Mbps * 1_000_000 / 8).
  static const double _defaultWifiBytesPerSec = 40 * 1000 * 1000 / 8; // 40 Mbps
  static const double _defaultCellularBytesPerSec =
      12 * 1000 * 1000 / 8; // 12 Mbps

  /// The last smoothed measured speed, or `null` if we've never recorded one.
  static double? get measuredBytesPerSecond {
    final value = KvStore.get<double>(_kSpeedKey);
    if (value == null || value <= 0 || !value.isFinite) return null;
    return value;
  }

  /// Record the throughput observed for a completed upload.
  ///
  /// Pass the full [fileSizeBytes] and the [elapsedMs] wall-clock time it took
  /// to upload. Resumed uploads should not be recorded since their elapsed
  /// time doesn't cover the whole file.
  static Future<void> recordSample({
    required int? fileSizeBytes,
    required int elapsedMs,
  }) async {
    if (fileSizeBytes == null || fileSizeBytes < _minBytesForSample) return;
    if (elapsedMs <= 0) return;

    final sample = fileSizeBytes / (elapsedMs / 1000.0);
    if (!sample.isFinite || sample <= 0) return;

    final prev = measuredBytesPerSecond;
    final next = prev == null
        ? sample
        : (prev * (1 - _emaAlpha)) + (sample * _emaAlpha);

    await KvStore.set(_kSpeedKey, next);
  }

  /// Estimate how long uploading [totalBytes] will take.
  ///
  /// Uses the measured speed when available, otherwise a generic wifi or
  /// cellular default based on [onWifi].
  static UploadTimeEstimate estimate({
    required int totalBytes,
    required bool onWifi,
  }) {
    final measured = measuredBytesPerSecond;
    final bytesPerSec =
        measured ??
        (onWifi ? _defaultWifiBytesPerSec : _defaultCellularBytesPerSec);

    final seconds = bytesPerSec <= 0 ? 0.0 : totalBytes / bytesPerSec;

    return UploadTimeEstimate(
      duration: Duration(seconds: seconds.ceil()),
      bytesPerSecond: bytesPerSec,
      basedOnMeasuredSpeed: measured != null,
    );
  }
}
