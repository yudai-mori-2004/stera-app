import "package:flutter/foundation.dart";
import "package:stera/src/services/foreground_notification_service/foreground_notification_service.dart";

/// Upload-specific layer over [ForegroundNotificationService]: owns the upload
/// notification channel, its fixed notification id, and the pause/resume/cancel
/// action semantics. Features unrelated to uploads should use
/// [ForegroundNotificationService] directly rather than this wrapper.
class UploadForegroundNotifier {
  UploadForegroundNotifier._();

  static const ForegroundNotificationChannel _channel =
      ForegroundNotificationChannel(
        id: "upload_service_channel",
        name: "Upload Service",
        description: "Shows progress of video uploads",
      );
  static const int _notificationId = 1001;

  static const String _cancelActionId = "cancel_uploads";
  static const String _pauseActionId = "pause_uploads";
  static const String _resumeActionId = "resume_uploads";

  static bool _isPaused = false;
  static bool get isPaused => _isPaused;

  /// Last known progress percent, kept so pause/resume re-renders preserve the
  /// "P%" copy instead of falling back to a vague title.
  static int _percent = 0;

  /// Seed the notification when a fresh batch starts at 0%. Clears any stale
  /// paused state from a prior session. [totalVideos] is accepted for call-site
  /// symmetry but no longer shown — the banner is percent-only.
  static Future<bool> start({required int totalVideos}) {
    _isPaused = false;
    _percent = 0;
    return _render();
  }

  /// Update the ongoing notification with live upload progress. [videoIndex]
  /// and [totalVideos] are accepted for call-site symmetry but no longer shown
  /// — the banner is percent-only.
  static Future<bool> updateProgress({
    required int videoIndex,
    required int totalVideos,
    required int percent,
  }) {
    _percent = percent.clamp(0, 100);
    return _render();
  }

  /// Update the ongoing upload notification to reflect paused/active state.
  static Future<bool> updatePausedState({required bool isPaused}) {
    _isPaused = isPaused;
    return _render();
  }

  /// Render the notification from the current paused state + last known
  /// progress. Title "Uploading Videos", body "25%" — matches the native
  /// background banner.
  ///
  /// A single notification (fixed [_notificationId]) is updated in place and
  /// quietly — no new banner pops on each progress tick. Only when the user has
  /// dismissed it do we re-present (alert) so the upload stays visible.
  static Future<bool> _render() async {
    final title = _isPaused ? "Uploads Paused" : "Uploading Videos";
    final body = _bodyText();
    final isActive = await ForegroundNotificationService.isNotificationActive(
      _notificationId,
    );
    return ForegroundNotificationService.updateForeground(
      channel: _channel,
      notificationId: _notificationId,
      title: title,
      body: body,
      progress: _percent,
      presentAlert: !isActive,
      actions: _actions(isPaused: _isPaused),
    );
  }

  static String _bodyText() {
    // Percent only — the batch "X/Y" count is omitted by request, matching the
    // native progress banner.
    if (_isPaused) {
      return "Paused - $_percent%";
    }
    return "$_percent%";
  }

  /// Dismiss the upload notification and stop the foreground service.
  static Future<bool> stopService() {
    _isPaused = false;
    _percent = 0;
    return ForegroundNotificationService.stopForeground(
      notificationId: _notificationId,
    );
  }

  static List<ForegroundNotificationAction> _actions({required bool isPaused}) =>
      [
        ForegroundNotificationAction(
          id: isPaused ? _resumeActionId : _pauseActionId,
          title: isPaused ? "Resume" : "Pause",
        ),
        const ForegroundNotificationAction(id: _cancelActionId, title: "Cancel"),
      ];

  static void setUploadPauseListener(VoidCallback onPause) =>
      ForegroundNotificationService.setActionListener(_pauseActionId, onPause);
  static void removeUploadPauseListener() =>
      ForegroundNotificationService.removeActionListener(_pauseActionId);

  static void setUploadResumeListener(VoidCallback onResume) =>
      ForegroundNotificationService.setActionListener(_resumeActionId, onResume);
  static void removeUploadResumeListener() =>
      ForegroundNotificationService.removeActionListener(_resumeActionId);

  static void setUploadCancelListener(VoidCallback onCancel) =>
      ForegroundNotificationService.setActionListener(_cancelActionId, onCancel);
  static void removeUploadCancelListener() =>
      ForegroundNotificationService.removeActionListener(_cancelActionId);
}
