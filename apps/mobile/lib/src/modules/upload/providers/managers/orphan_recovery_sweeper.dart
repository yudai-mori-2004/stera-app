import "dart:async";
import "dart:developer" as dev;

import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/modules/upload/providers/managers/video_source_manager.dart";

/// Post-exit safety net for takes that finished on disk but never got their
/// Upload row (missed finalize event, app backgrounded mid-finalize, …) and
/// would otherwise only appear after running RecoverRecordingsAction.
///
/// [scheduleAfterRecorderExit] runs the same orphan-session recovery as that
/// action every [_interval] after the AR recorder page is torn down, up to
/// [_sweepCount] times. The window is generous (~5 min) because recovery only
/// adopts a session once its mcap is finalized (trailing magic — see
/// [McapFinalization]) and the footer write for a long recording can take
/// minutes; the normal `createUploadFromSessionDir` path defers to this sweep
/// when it times out waiting. Recovery is idempotent (sessions already in the
/// uploads table are skipped), so overlapping schedules or a manual recover
/// tap in between are harmless. Static so the timer chain survives the
/// recorder page's dispose.
class OrphanRecoverySweeper {
  OrphanRecoverySweeper._();

  static const Duration _interval = Duration(seconds: 15);
  static const int _sweepCount = 20;

  static Timer? _timer;
  static int _sweepsLeft = 0;

  /// (Re)arms the sweep chain. A new recorder exit while a chain is still
  /// pending restarts it from sweep one.
  static void scheduleAfterRecorderExit() {
    // An auth-free build has no uploads to recover into. The guard lives here
    // rather than at the `ArRecorderPage.dispose()` call site so the recorder
    // stays upload-agnostic — and because this sweep is otherwise the one path
    // that would open the Drift DB and write Upload rows after every recording.
    if (AppConfig.noAuthMode) return;

    _timer?.cancel();
    _sweepsLeft = _sweepCount;
    dev.log(
      "OrphanRecoverySweeper: armed — $_sweepCount sweeps, "
      "${_interval.inSeconds}s apart",
    );
    _timer = Timer.periodic(_interval, (timer) {
      _sweepsLeft -= 1;
      if (_sweepsLeft <= 0) {
        timer.cancel();
        _timer = null;
      }
      unawaited(_sweep());
    });
  }

  static Future<void> _sweep() async {
    try {
      final recovered = await VideoSourceManager().recoverOrphanedSessions();
      dev.log(
        "OrphanRecoverySweeper: sweep recovered ${recovered.length} "
        "session(s), $_sweepsLeft sweep(s) left",
      );
    } catch (e) {
      dev.log("OrphanRecoverySweeper: sweep failed - $e");
    }
  }
}
