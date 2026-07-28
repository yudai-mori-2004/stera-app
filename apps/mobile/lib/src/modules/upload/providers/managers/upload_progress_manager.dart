import "dart:async";
import "package:stera/src/modules/upload_estimate/services/upload_speed_tracker.dart";
import "package:stera/src/services/upload_service/channels/upload_foreground_notifier.dart";
import "package:stera/src/services/upload_service/data/typedef/upload_progress.dart";
import "package:stera/src/services/upload_service/uploads_service.dart";
import "package:flutter/foundation.dart";

/// Manages upload progress state and throttles UI updates.
///
/// This manager subscribes to the [UploadsService.progressStream] and
/// exposes the current progress to the UI via [UploadProvider].
///
/// Throttling is applied to reduce UI rebuilds:
/// - Dynamic threshold based on file size (larger files = more frequent updates)
/// - Always notifies on null (upload finished) or 100% (upload complete)
class UploadProgressManager extends ChangeNotifier {
  UploadProgressManager._internal() {
    _startListening();
  }

  static final UploadProgressManager _instance =
      UploadProgressManager._internal();
  static UploadProgressManager get instance => _instance;

  StreamSubscription<UploadProgress?>? _subscription;

  UploadProgress? _currentProgress;
  UploadProgress? get currentProgress => _currentProgress;

  int _lastNotifiedProgress = -1;
  int _lastNotificationMilestone = -1;
  int? _currentFileSize;

  /// File size thresholds that control how often the ongoing upload
  /// notification is updated.
  static const int _notif5GbThreshold = 5 * 1024 * 1024 * 1024; // 5 GB
  static const int _notif10GbThreshold = 10 * 1024 * 1024 * 1024; // 10 GB

  /// Notification update step (%) based on the current file size:
  /// - > 10 GB: every 5%
  /// - > 5 GB:  every 10%
  /// - else:    every 25%
  int get _notificationStep {
    final size = _currentFileSize;
    if (size != null && size > _notif10GbThreshold) return 5;
    if (size != null && size > _notif5GbThreshold) return 10;
    return 25;
  }

  /// Whole-second ETA last pushed to the UI. The progress %% can sit on the
  /// same throttle bucket for many seconds while the countdown keeps changing,
  /// so we also notify when this ticks — otherwise the ETA renders once and then
  /// appears frozen.
  int? _lastNotifiedEtaSeconds;

  /// Live ETA for the upload currently in flight, recomputed on every
  /// progress event from the observed throughput. `null` until a speed is
  /// known (no historical sample and no progress delta yet) or when nothing
  /// is uploading.
  Duration? _currentEta;
  Duration? get currentEta => _currentEta;

  int? _etaUploadId;
  DateTime? _lastSampleAt;
  double? _lastSampleBytes;
  double? _emaBytesPerSec;

  /// Weight of the newest instantaneous speed sample. Low enough that one
  /// fast/slow chunk doesn't whip the ETA around.
  static const double _etaEmaAlpha = 0.3;

  /// Ignore deltas measured over less than this — chunk batches that land
  /// within the same flush would read as absurdly high speeds.
  static const double _minSampleSeconds = 0.5;

  /// A gap this long means the upload sat paused/stalled; re-baseline
  /// instead of folding the dead time into the speed estimate.
  static const double _staleSampleSeconds = 120;

  /// File size thresholds in bytes
  static const int _smallFileThreshold = 100 * 1024 * 1024; // 100 MB
  static const int _mediumFileThreshold = 500 * 1024 * 1024; // 500 MB
  static const int _largeFileThreshold = 1024 * 1024 * 1024; // 1 GB

  /// Progress thresholds (%) for different file sizes
  /// Larger files get more frequent updates (smoother progress bar)
  /// Smaller files get fewer updates (they complete quickly anyway)
  static const int _smallFileProgressThreshold = 8; // Update every 8%
  static const int _mediumFileProgressThreshold = 5; // Update every 5%
  static const int _largeFileProgressThreshold = 3; // Update every 3%
  static const int _veryLargeFileProgressThreshold = 2; // Update every 2%

  /// Get dynamic threshold based on current file size
  int get _progressThreshold {
    final size = _currentFileSize;
    if (size == null) return _smallFileProgressThreshold;

    if (size >= _largeFileThreshold) {
      return _veryLargeFileProgressThreshold; // 1GB+ files: update every 2%
    } else if (size >= _mediumFileThreshold) {
      return _largeFileProgressThreshold; // 500MB-1GB: update every 3%
    } else if (size >= _smallFileThreshold) {
      return _mediumFileProgressThreshold; // 100MB-500MB: update every 5%
    } else {
      return _smallFileProgressThreshold; // <100MB: update every 8%
    }
  }

  /// Update the current file size for dynamic throttling
  void setCurrentFileSize(int? fileSize) {
    _currentFileSize = fileSize;
  }

  void _startListening() {
    _subscription = UploadsService.instance.progressStream.listen((progress) {
      _currentProgress = progress;

      if (progress == null) {
        _lastNotifiedProgress = -1;
        _lastNotificationMilestone = -1;
        _lastNotifiedEtaSeconds = null;
        _currentFileSize = null;
        _resetEta();
        notifyListeners();
        return;
      }

      if (_etaUploadId != null && _etaUploadId != progress.uploadId) {
        _lastNotificationMilestone = -1;
      }
      _updateEta(progress);

      // Notify when the progress %% crosses its (size-dependent) throttle bucket
      // OR when the live ETA ticks by a whole second — the latter keeps the
      // countdown moving even while progress sits in the same bucket.
      final progressCrossed =
          progress.progress == 100 ||
          progress.progress == 0 ||
          (progress.progress - _lastNotifiedProgress).abs() >=
              _progressThreshold;
      final etaSeconds = _currentEta?.inSeconds;
      final etaChanged = etaSeconds != _lastNotifiedEtaSeconds;

      // Keep the ongoing upload notification in sync at size-dependent
      // milestones (25%/10%/5% by file size) — pause/resume re-renders are
      // handled separately by the queue.
      if (_crossedNotificationMilestone(progress.progress)) {
        unawaited(
          UploadForegroundNotifier.updateProgress(
            videoIndex: progress.videoIndex,
            totalVideos: progress.totalVideos,
            percent: progress.progress,
          ),
        );
      }

      if (progressCrossed || etaChanged) {
        _lastNotifiedProgress = progress.progress;
        _lastNotifiedEtaSeconds = etaSeconds;
        notifyListeners();
      }
    });
  }

  /// Fold the latest progress event into the live speed estimate and
  /// recompute [currentEta].
  ///
  /// Bytes done are derived from the chunk counts (finer than the integer
  /// percent). The speed is an EMA of instantaneous deltas, seeded with the
  /// historical smoothed speed from [UploadSpeedTracker] so an ETA shows
  /// immediately for returning users.
  void _updateEta(UploadProgress progress) {
    final size = _currentFileSize;
    if (size == null || size <= 0 || progress.total <= 0) {
      _currentEta = null;
      return;
    }

    final bytesDone = size * (progress.current / progress.total);
    final now = DateTime.now();

    if (_etaUploadId != progress.uploadId) {
      _etaUploadId = progress.uploadId;
      _lastSampleAt = now;
      _lastSampleBytes = bytesDone;
      _emaBytesPerSec = UploadSpeedTracker.measuredBytesPerSecond;
    } else {
      final dt =
          now.difference(_lastSampleAt!).inMilliseconds / 1000.0;
      final db = bytesDone - _lastSampleBytes!;
      if (db < 0 || dt > _staleSampleSeconds) {
        // Backward jump (resume re-sync) or a pause/stall gap: re-baseline
        // rather than poisoning the speed estimate.
        _lastSampleAt = now;
        _lastSampleBytes = bytesDone;
      } else if (db > 0 && dt >= _minSampleSeconds) {
        final instant = db / dt;
        final prev = _emaBytesPerSec;
        _emaBytesPerSec = prev == null
            ? instant
            : (prev * (1 - _etaEmaAlpha)) + (instant * _etaEmaAlpha);
        _lastSampleAt = now;
        _lastSampleBytes = bytesDone;
      }
      // db == 0 or dt too small: keep the baseline so the delta accumulates
      // into the next accepted sample.
    }

    final speed = _emaBytesPerSec;
    if (speed == null || speed <= 0 || !speed.isFinite) {
      _currentEta = null;
      return;
    }
    final remaining = (size - bytesDone).clamp(0, size).toDouble();
    _currentEta = Duration(seconds: (remaining / speed).ceil());
  }

  /// True when [percent] crosses a new size-dependent notification milestone
  /// (see [_notificationStep]). 100% always counts as a milestone.
  bool _crossedNotificationMilestone(int percent) {
    final step = _notificationStep;
    // Highest step-aligned milestone at or below the current percent (or 100).
    final milestone = percent >= 100 ? 100 : (percent ~/ step) * step;
    if (milestone > 0 && milestone > _lastNotificationMilestone) {
      _lastNotificationMilestone = milestone;
      return true;
    }
    return false;
  }

  void _resetEta() {
    _currentEta = null;
    _etaUploadId = null;
    _lastSampleAt = null;
    _lastSampleBytes = null;
    _emaBytesPerSec = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void reset() {
    _currentProgress = null;
    _lastNotifiedProgress = -1;
    _lastNotificationMilestone = -1;
    _lastNotifiedEtaSeconds = null;
    _currentFileSize = null;
    _resetEta();
    notifyListeners();
  }
}
