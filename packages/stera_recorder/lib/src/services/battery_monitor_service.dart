import "dart:async";
import "dart:developer" as dev;

import "package:battery_plus/battery_plus.dart";

/// Watches the device battery level while an AR recording is active and fires
/// callbacks as it crosses key thresholds.
///
/// - Plays a low-battery warning the first time the level drops to [30],
///   again at [25], and a final time at [20] percent (via
///   [onLowBatteryWarning]).
/// - Requests an auto-stop the moment the level reaches [criticalThreshold]
///   (19%) or below (via [onCriticalBattery]).
///
/// `battery_plus` exposes the level only as a one-shot future (there is no
/// level-change stream), so we poll on a fixed cadence. Battery drains slowly,
/// so a 20 s cadence is responsive enough while staying cheap.
class BatteryMonitorService {
  BatteryMonitorService({
    required this.onLowBatteryWarning,
    required this.onCriticalBattery,
  });

  /// Invoked once per crossed warning threshold (30%, 25%, then 20%).
  final Future<void> Function() onLowBatteryWarning;

  /// Invoked when the level reaches [criticalThreshold] or below. The monitor
  /// stops itself after firing so it never fires twice.
  final Future<void> Function() onCriticalBattery;

  static const List<int> _warningThresholds = [30, 25, 20];

  /// Auto-stop level. All user-facing copy advertises 20% as the cutoff; the
  /// actual stop fires one point below it so a take still survives at exactly
  /// 20% and the advertised threshold reads as the hard limit.
  static const int criticalThreshold = 19;
  static const Duration _pollInterval = Duration(seconds: 20);

  /// A recording may not be *started* below this level (the device is too close
  /// to the [criticalThreshold] auto-stop to be worth beginning).
  static const int minStartThreshold = 22;

  /// Starting a recording at or below this level is allowed but warns the user
  /// audibly (via the "warn about low battery" cue).
  static const int warnStartThreshold = 30;

  /// One-shot read of the current battery level (0–100), or null if the
  /// platform read fails. Usable without [start] — the pre-flight start check
  /// calls this before the monitor is running.
  Future<int?> currentLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      dev.log("BatteryMonitorService: currentLevel failed - $e");
      return null;
    }
  }

  final Battery _battery = Battery();
  Timer? _timer;
  bool _running = false;
  bool _critical = false;
  final Set<int> _firedWarnings = <int>{};

  bool get isRunning => _running;

  /// Begins polling. Re-arms warning thresholds so a fresh recording session
  /// re-evaluates the current (possibly still-low) level. No-op if already
  /// running.
  void start() {
    if (_running) return;
    _running = true;
    _critical = false;
    _firedWarnings.clear();
    dev.log("BatteryMonitorService: started");
    // Check immediately, then on the poll cadence.
    unawaited(_check());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_check()));
  }

  /// Stops polling. Safe to call repeatedly.
  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    dev.log("BatteryMonitorService: stopped");
  }

  Future<void> _check() async {
    if (!_running) return;
    int level;
    try {
      level = await _battery.batteryLevel;
    } catch (e) {
      dev.log("BatteryMonitorService: batteryLevel failed - $e");
      return;
    }
    if (!_running) return;

    if (level <= criticalThreshold) {
      if (_critical) return;
      _critical = true;
      dev.log("BatteryMonitorService: critical at $level% — requesting stop");
      // Stop polling before firing so a slow stop can't trigger a second call.
      stop();
      await onCriticalBattery();
      return;
    }

    // Warn once per zone entry, never once-per-threshold. Starting a recording
    // already below 25% crosses both 30% and 25% in the same check; firing for
    // each would play the warning twice back-to-back. Collect every newly
    // crossed threshold, mark them all fired, but sound the cue a single time.
    final crossed = _warningThresholds
        .where((t) => level <= t && !_firedWarnings.contains(t))
        .toList();
    if (crossed.isEmpty) return;
    _firedWarnings.addAll(crossed);
    dev.log(
      "BatteryMonitorService: crossed ${crossed.join("/")}% (level=$level%) — warning",
    );
    await onLowBatteryWarning();
  }

  void dispose() => stop();
}
