import "package:stera/src/services/kv_store/kv_store.dart";
import "package:stera/src/services/permission_service/permission_service.dart";
import "package:stera_recorder/stera_recorder.dart";

/// Backs the recorder's settings persistence with the app's [KvStore] so the
/// recorder shares the single `SharedPreferences` instance (and the keys it
/// already wrote before the package was extracted).
class KvStoreRecorderPreferences implements RecorderPreferences {
  const KvStoreRecorderPreferences();

  @override
  T? get<T>(String key, {T? defaultValue}) =>
      KvStore.get<T>(key, defaultValue: defaultValue);

  @override
  Future<void> set(String key, Object value) => KvStore.set(key, value);
}

/// Backs the recorder's permission checks with the app's [PermissionService] so
/// there stays exactly one camera-permission path.
class AppRecorderPermissions implements RecorderPermissions {
  const AppRecorderPermissions();

  @override
  Future<bool> isCameraPermissionGranted() =>
      PermissionService.isCameraPermissionGranted();

  @override
  Future<bool> openSettings() => PermissionService.openSettings();
}
