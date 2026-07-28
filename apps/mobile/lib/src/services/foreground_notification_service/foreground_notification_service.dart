import "dart:developer";
import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";

/// Channel descriptor for an ongoing (foreground/progress) notification.
class ForegroundNotificationChannel {
  const ForegroundNotificationChannel({
    required this.id,
    required this.name,
    this.description = "",
  });

  final String id;
  final String name;
  final String description;
}

/// An action button rendered on an ongoing notification (Android only). Taps
/// are dispatched to listeners registered via
/// [ForegroundNotificationService.setActionListener] keyed by [id].
class ForegroundNotificationAction {
  const ForegroundNotificationAction({required this.id, required this.title});

  final String id;
  final String title;
}

/// Generic, app-wide notification service built on flutter_local_notifications.
///
/// Two reusable capabilities, neither coupled to any feature:
///   * [showNotification] — fire-and-forget one-time notifications;
///   * [startForeground] / [updateForeground] / [stopForeground] — a persistent
///     ongoing (progress) notification that, on Android, runs as a foreground
///     service to keep the app alive during long-running work.
///
/// Action-button taps are routed to listeners registered by action id via
/// [setActionListener] / [removeActionListener]. Domain-specific wrappers
/// (e.g. the upload notifier) layer their own channel, titles and action
/// semantics on top of this.
class ForegroundNotificationService {
  ForegroundNotificationService._();

  // General one-time notification channel.
  static const String _generalChannelId = "general_notifications";
  static const String _generalChannelName = "General Notifications";
  static const String _generalChannelDescription = "General app notifications";

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Action-tap listeners keyed by action id.
  static final Map<String, VoidCallback> _actionListeners = {};

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;

    const AndroidInitializationSettings android = AndroidInitializationSettings(
      "@mipmap/ic_launcher",
    );
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notifications.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    await _createAndroidChannel(
      const AndroidNotificationChannel(
        _generalChannelId,
        _generalChannelName,
        description: _generalChannelDescription,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    _initialized = true;
  }

  static Future<void> _createAndroidChannel(
    AndroidNotificationChannel channel,
  ) async {
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId == null) return;
    _actionListeners[actionId]?.call();
  }

  /// Register a tap listener for a notification [actionId]. Overwrites any
  /// existing listener for the same id.
  static void setActionListener(String actionId, VoidCallback onAction) {
    _actionListeners[actionId] = onAction;
  }

  static void removeActionListener(String actionId) {
    _actionListeners.remove(actionId);
  }

  /// Show a one-time local notification. Returns true on success.
  static Future<bool> showNotification({
    required String title,
    required String body,
    int? notificationId,
  }) async {
    try {
      await _ensureInitialized();

      final id =
          notificationId ?? DateTime.now().millisecondsSinceEpoch % 2147483647;

      const AndroidNotificationDetails android = AndroidNotificationDetails(
        _generalChannelId,
        _generalChannelName,
        channelDescription: _generalChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        showWhen: true,
      );
      const DarwinNotificationDetails ios = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _notifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: android,
          iOS: ios,
        ),
      );
      return true;
    } catch (e) {
      log("Error showing notification: $e");
      return false;
    }
  }

  /// Start an ongoing (progress) notification. On Android this launches a
  /// foreground service so the OS keeps the app alive during the work. Pass a
  /// non-null [progress] (0–100) to show a determinate progress bar.
  static Future<bool> startForeground({
    required ForegroundNotificationChannel channel,
    required int notificationId,
    required String title,
    required String body,
    int? progress,
    List<ForegroundNotificationAction> actions = const [],
  }) async {
    try {
      await _ensureInitialized();
      await _createForegroundChannel(channel);

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.startForegroundService(
            id: notificationId,
            title: title,
            body: body,
            notificationDetails: _ongoingAndroidDetails(
              channel: channel,
              progress: progress,
              actions: actions,
            ),
          );
      return true;
    } catch (e) {
      log("Error starting foreground notification: $e");
      return false;
    }
  }

  /// Update the ongoing notification's text, progress and actions.
  ///
  /// [presentAlert] controls whether iOS re-presents the banner. Pass `false`
  /// to quietly update the existing notification in place (no new banner); pass
  /// `true` only when the notification needs to (re)appear — e.g. it was
  /// dismissed by the user.
  static Future<bool> updateForeground({
    required ForegroundNotificationChannel channel,
    required int notificationId,
    required String title,
    required String body,
    int? progress,
    bool presentAlert = false,
    List<ForegroundNotificationAction> actions = const [],
  }) async {
    try {
      await _ensureInitialized();
      await _createForegroundChannel(channel);

      await _notifications.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _ongoingAndroidDetails(
            channel: channel,
            progress: progress,
            actions: actions,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: presentAlert,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
      return true;
    } catch (e) {
      log("Error updating foreground notification: $e");
      return false;
    }
  }

  /// Whether a notification with [notificationId] is currently shown in the
  /// system tray / notification center. Used to detect user dismissal so the
  /// caller can decide between a quiet in-place update and re-presenting it.
  static Future<bool> isNotificationActive(int notificationId) async {
    try {
      await _ensureInitialized();
      final active = await _notifications.getActiveNotifications();
      return active.any((n) => n.id == notificationId);
    } catch (e) {
      log("Error checking active notifications: $e");
      return false;
    }
  }

  /// Stop the foreground service (Android) and dismiss the notification.
  static Future<bool> stopForeground({required int notificationId}) async {
    try {
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.stopForegroundService();
      await _notifications.cancel(id: notificationId);
      return true;
    } catch (e) {
      log("Error stopping foreground notification: $e");
      return false;
    }
  }

  static Future<void> _createForegroundChannel(
    ForegroundNotificationChannel channel,
  ) {
    return _createAndroidChannel(
      AndroidNotificationChannel(
        channel.id,
        channel.name,
        description: channel.description,
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );
  }

  static AndroidNotificationDetails _ongoingAndroidDetails({
    required ForegroundNotificationChannel channel,
    int? progress,
    List<ForegroundNotificationAction> actions = const [],
  }) {
    return AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showProgress: progress != null,
      maxProgress: 100,
      progress: progress ?? 0,
      indeterminate: false,
      actions: [
        for (final a in actions)
          AndroidNotificationAction(
            a.id,
            a.title,
            cancelNotification: false,
            showsUserInterface: true,
          ),
      ],
    );
  }
}
