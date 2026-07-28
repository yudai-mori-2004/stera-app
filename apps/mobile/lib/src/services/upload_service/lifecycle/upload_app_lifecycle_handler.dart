import "dart:io";

import "package:flutter/material.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/services/upload_service/channels/ios_windowed_uploader_service.dart";
import "package:stera/src/services/upload_service/coordinator/windowed_upload_coordinator.dart";

/// Upload-only app lifecycle reactions: hand notification duty to the native
/// uploader when we lose the screen, and drain the windowed-engine journal on
/// return. Nothing else lives here — unrelated lifecycle concerns belong to
/// their own widgets.
abstract final class UploadAppLifecycleHandler {
  /// Native defaults to "backgrounded"; assert foreground on cold start so the
  /// in-app UI owns upload progress while we're visible (`resumed` may not fire
  /// on launch).
  static void onColdStart() {
    if (AppConfig.noAuthMode) return;
    _setForegrounded(true);
  }

  static void handleState(AppLifecycleState state) {
    // There is no windowed uploader to hand notification duty to. Guarding in
    // the owning class beats guarding at both `StartupView` call sites.
    if (AppConfig.noAuthMode) return;

    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Dart is frozen and the in-app progress UI is hidden once backgrounded,
        // so native owns the progress/stall/finish banners. (`inactive` is a
        // transient interruption — e.g. the app switcher — so we keep foreground
        // ownership there.)
        _setForegrounded(false);
        return;
      case AppLifecycleState.inactive:
        return;
      case AppLifecycleState.resumed:
        // Reclaim notification ownership — the in-app UI is visible again.
        _setForegrounded(true);
        // Windowed uploads (iOS) keep transferring out-of-process while we're
        // backgrounded. On return, drain the native journal into Drift,
        // reconcile against storage, and re-pump any session that stalled — so
        // background progress is reflected and the upload always moves toward
        // completion. Fire-and-forget + guarded so a rapid background/foreground
        // toggle can't pile up or block the UI.
        if (Platform.isIOS) {
          WindowedUploadCoordinator.instance.resumeOnLaunch().catchError((
            Object e,
          ) {
            debugPrint("⚠️ windowed resume on foreground failed: $e");
          });
        }
        return;
    }
  }

  static void _setForegrounded(bool foregrounded) {
    if (!Platform.isIOS) return;
    IosWindowedUploaderService.instance
        .setAppForegrounded(foregrounded: foregrounded)
        .catchError((Object e) {
          debugPrint("⚠️ setAppForegrounded failed: $e");
          return null;
        });
  }
}
