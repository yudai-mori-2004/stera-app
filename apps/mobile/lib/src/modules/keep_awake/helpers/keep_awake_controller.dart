import "package:flutter/foundation.dart";
import "package:stera/src/services/kv_store/kv_store.dart";
import "package:wakelock_plus/wakelock_plus.dart";

/// Owns the screen wakelock behind a single persisted preference. Decoupled
/// from any page so the control can live inline (profile toggle, header action,
/// progress-card banner) — every surface reads and writes the same value, so
/// toggling anywhere stays in sync and survives relaunches.
abstract final class KeepAwakeController {
  /// The persisted "keep screen on" preference and, by extension, whether the
  /// wakelock is held. Single source of truth for every keep-awake control.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static Future<void> restore() async {
    final saved =
        KvStore.get<bool>(KvStoreKeys.keepScreenAwake, defaultValue: false) ??
        false;
    enabled.value = saved;
    await _syncWakelock(saved);
  }

  static Future<void> setEnabled(bool on) async {
    if (enabled.value == on) return;
    enabled.value = on;
    await KvStore.set(KvStoreKeys.keepScreenAwake, on);
    await _syncWakelock(on);
  }

  static Future<void> toggle() => setEnabled(!enabled.value);

  static Future<void> _syncWakelock(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      enabled.value = !on;
      debugPrint("⚠️ keep-awake toggle failed: $e");
    }
  }
}
