import "dart:async";
import "dart:io";

import "package:better_auth_flutter/better_auth_flutter.dart" as ba;
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/theme/theme_notifier.dart";
import "package:stera/src/modules/auth/data/repo/auth_repo.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/keep_awake/helpers/keep_awake_controller.dart";
import "package:stera/src/modules/startup/data/app_state.dart";
import "package:stera/src/services/app_info/app_info.dart";
import "package:stera/src/services/connectivity_service/connectivity_service.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/db/upload_session_db.dart";
import "package:stera/src/services/kv_store/kv_store.dart";
import "package:stera/src/services/legacy_upload_migration_service/legacy_upload_migration_service.dart";
import "package:stera/src/services/secure_storage/secure_storage.dart";
import "package:stera/src/services/upload_service/coordinator/windowed_upload_coordinator.dart";

/// Drives the app's cold-boot bootstrap and exposes it as an [AppState] via a
/// [ValueNotifier] so `StartupView` can render splash / app / error without a
/// dedicated route. Replaces the old imperative `bootstrap()` in `main.dart`.
///
/// Platform initialization runs exactly once; [retryInitialization] re-runs only
/// the recoverable tail (session restore) so a transient network failure can be
/// retried without re-initializing Better Auth et al.
class StartupViewModel {
  StartupViewModel({AuthProvider? authProvider}) : _authProvider = authProvider;

  /// Null in a `NO_AUTH_MODE` build, where `AuthProvider` isn't registered at
  /// all. Every auth step below is skipped alongside it.
  final AuthProvider? _authProvider;

  final ValueNotifier<AppState> appStateNotifier = ValueNotifier(
    const InitializingApp(),
  );

  bool _platformReady = false;

  Future<void> initializeApp() async {
    appStateNotifier.value = const InitializingApp();

    try {
      await _initializePlatform();

      // Restore the auth session before the router mounts, so its redirect
      // resolves against a known auth state on the first evaluation. No-op in
      // no-auth mode, where the router has no redirect to satisfy.
      await _authProvider?.init();

      appStateNotifier.value = const AppInitialized();
    } catch (e, st) {
      debugPrint("⚠️ app initialization failed: $e");
      appStateNotifier.value = AppInitializationError(e, st);
    }
  }

  /// One-time platform + service setup. Guarded so [retryInitialization] never
  /// re-runs non-idempotent steps (e.g. `BetterAuthFlutter.initialize`).
  Future<void> _initializePlatform() async {
    if (_platformReady) return;

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    // These run in every build. `KvStore` in particular is *required* by the
    // capture path: `KvStoreRecorderPreferences` reads it synchronously, so
    // without init every recorder setting silently resets each launch.
    await KvStore.init();
    await KeepAwakeController.restore();
    await ThemeNotifier().loadThemeMode();
    await AppInfo.init();
    await SecureStorage.init();

    // Everything below is auth or upload machinery. In no-auth mode Better Auth
    // would be handed the empty string from a missing `*_AUTH_BASE_URL` and take
    // the whole boot down into `StartupErrorView`; the upload steps are the only
    // bootstrap calls that open Drift at all.
    if (!AppConfig.noAuthMode) {
      await ba.BetterAuthFlutter.initialize(
        url: AppConfig.authBaseUrl,
        enableLogging: kDebugMode,
      );
      await AuthRepo.init();
      // Sole consumer is `UploadQueueManager`, so with no uploads this would be
      // a permanent subscription nothing reads.
      ConnectivityService.instance.startMonitoring();

      _scheduleBackgroundCleanup();

      if (Platform.isIOS) {
        // Migrate before the windowed uploader starts so it observes the
        // migrated session state, not the legacy layout.
        await LegacyUploadMigrationService.instance.run();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await WindowedUploadCoordinator.instance.start();
          } catch (e) {
            debugPrint("⚠️ windowed uploader start failed (non-fatal): $e");
          }
        });
      }
    }

    _platformReady = true;
  }

  /// Best-effort maintenance that must not block or fail startup.
  void _scheduleBackgroundCleanup() {
    Future.microtask(() async {
      await UploadDb.instance.deleteCanceledUploads();
      await UploadDb.instance.deleteCompletedUploads();
      if (Platform.isIOS) {
        await UploadSessionDb.instance.deleteTerminalSessions();
      }
    });
  }

  Future<void> retryInitialization() async {
    await initializeApp();
  }

  void dispose() {
    appStateNotifier.dispose();
  }
}
