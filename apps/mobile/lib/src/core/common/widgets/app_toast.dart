import "dart:math" as math;

import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_toast_motion.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:toastification/toastification.dart";

enum AppToastType {
  success,
  error,
  warning,
  info;

  IconData iconData(IconData? customIcon) {
    if (customIcon != null) return customIcon;
    return switch (this) {
      AppToastType.success => Icons.check_circle_outline,
      AppToastType.error => Icons.error_outline,
      AppToastType.warning => Icons.warning_amber_outlined,
      AppToastType.info => Icons.info_outline,
    };
  }

  Color iconColor(BuildContext context, Color? customColor) {
    if (customColor != null) return customColor;

    return switch (this) {
      AppToastType.success => context.colors.green,
      AppToastType.error => context.colors.red,
      AppToastType.warning => context.colors.yellow,
      AppToastType.info => context.colors.blue,
    };
  }

  Color backgroundColor(BuildContext context, Color? customColor) {
    if (customColor != null) return customColor;
    // Elevated card surface: light = white, dark = charcoal (not `surfaceWhite`, which stays #FFF in both themes).
    return context.colors.surfaceSecondary;
  }

  Color textColor(BuildContext context) {
    return context.colors.textPrimary;
  }

  Color descriptionTextColor(BuildContext context) {
    return context.colors.textSecondary;
  }

  Color actionButtonColor(BuildContext context) {
    return context.colors.blue;
  }

  Color borderColor(BuildContext context) {
    return context.colors.borderDefault;
  }
}

class AppToast {
  static Toastification toastification = Toastification();
  static GlobalKey<NavigatorState>? navigatorKey;
  static bool? isInitialized;

  /// Toastification item ids of the toasts currently on screen, keyed by
  /// message identity. Lets a duplicate refresh the toast that's already
  /// showing instead of stacking a copy of it.
  static final Map<String, String> _liveToastIdByKey = {};

  /// When each live toast last absorbed a duplicate. Repeats inside
  /// [_refreshThrottle] are swallowed entirely so a burst of identical
  /// failures reads as a single shake, not a vibrating toast.
  static final Map<String, DateTime> _lastRefreshAt = {};
  static const Duration _refreshThrottle = Duration(milliseconds: 500);

  static void init({required GlobalKey<NavigatorState> key}) {
    navigatorKey = key;
    isInitialized = true;
  }

  /// Drops registry entries whose toast has already left the screen.
  static void _pruneDismissed() {
    _liveToastIdByKey.removeWhere(
      (_, id) => toastification.findToastificationItem(id) == null,
    );
    _lastRefreshAt.removeWhere((key, _) => !_liveToastIdByKey.containsKey(key));
  }

  static void show({
    BuildContext? context,
    required String title,
    IconData? icon,
    String? description,
    AppToastType appToastType = AppToastType.error,
    Color? appToastBgColor,
    Color? appToastIconColor,
    int? holdDuration,
    bool? showActionButton,
    String? actionLabel,
    void Function()? onActionPressed,
    bool showCloseIcon = false,
    bool autoDismiss = true,
    Alignment position = Alignment.topCenter,
  }) {
    if (isInitialized != true && context == null) {
      throw Exception("AppToast not initialized. Call AppToast.init() first.");
    }

    // Identical message already on screen: a second copy tells the user
    // nothing new. Re-show the same toast at the front of the stack with a
    // fresh timer and shake it — "this just happened again" — instead of
    // piling up duplicates.
    final key = "$appToastType|$title|$description|$position";
    _pruneDismissed();
    final liveId = _liveToastIdByKey[key];
    final live = liveId == null
        ? null
        : toastification.findToastificationItem(liveId);
    var shakeOnAppear = false;
    if (live != null) {
      final lastRefresh = _lastRefreshAt[key];
      final now = DateTime.now();
      if (lastRefresh != null &&
          now.difference(lastRefresh) < _refreshThrottle) {
        return;
      }
      _lastRefreshAt[key] = now;
      // Instant removal: the replacement renders in the same slot on the same
      // frame, so the user sees one continuous toast that jumps to the front
      // and shakes rather than a dismiss-and-reshow.
      toastification.dismiss(live, showRemoveAnimation: false);
      shakeOnAppear = true;
    }

    if (!shakeOnAppear) {
      // A new toast lands in the hand as well as on screen. Duplicates are
      // excluded — the shake fires its own haptic.
      switch (appToastType) {
        case AppToastType.error:
        case AppToastType.warning:
          HapticFeedback.mediumImpact();
        case AppToastType.success:
        case AppToastType.info:
          HapticFeedback.lightImpact();
      }
    }

    final item = toastification.showCustom(
      context: isInitialized != true ? context : navigatorKey?.currentContext,
      overlayState: navigatorKey?.currentState?.overlay,
      autoCloseDuration: autoDismiss
          ? Duration(seconds: holdDuration ?? 3)
          : null,
      // A refresh replaces a toast that's already visible — near-instant
      // entrance so it reads as the same card shaking, not a new arrival.
      animationDuration: shakeOnAppear
          ? const Duration(milliseconds: 100)
          : const Duration(milliseconds: 500),
      animationBuilder: (context, animation, alignment, child) =>
          AppToastTransition(
            animation: animation,
            alignment: alignment,
            child: child,
          ),
      alignment: position,
      builder: (context, holder) {
        Widget toast = Container(
          decoration: BoxDecoration(
            color: appToastType.backgroundColor(context, appToastBgColor),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: appToastType.borderColor(context),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: context.colors.neutralBlack.withValues(
                  alpha: context.isDarkMode ? 0.5 : 0.1,
                ),
                blurRadius: context.isDarkMode ? 12 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                appToastType.iconData(icon),
                color: appToastType.iconColor(context, appToastIconColor),
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppType.md,
                        fontWeight: AppType.semibold,
                        color: appToastType.textColor(context),
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: AppType.sm,
                          fontWeight: AppType.medium,
                          color: appToastType.descriptionTextColor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showActionButton == true) ...[
                const SizedBox(width: AppSpacing.sm),
                Pressable(
                  pressedScale: 0.9,
                  onTap: onActionPressed,
                  child: Text(
                    actionLabel ?? "Undo",
                    style: TextStyle(
                      fontSize: AppType.md,
                      fontWeight: AppType.medium,
                      color: appToastType.actionButtonColor(context),
                    ),
                  ),
                ),
              ],
              if (showCloseIcon) ...[
                const SizedBox(width: AppSpacing.sm),
                Pressable(
                  pressedScale: 0.9,
                  onTap: () => toastification.dismiss(holder),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: appToastType.textColor(context),
                  ),
                ),
              ],
            ],
          ),
        );

        return _ShakeOnAppear(
          active: shakeOnAppear,
          child: AppToastDismissible(
            key: Key("dismiss-${holder.id}"),
            // The pill has already animated itself off screen by this point,
            // so the host must not play its own removal animation on top.
            onDismissed: () =>
                toastification.dismiss(holder, showRemoveAnimation: false),
            child: toast,
          ),
        );
      },
    );

    _liveToastIdByKey[key] = item.id;
  }

  /// Convenience method for success toast
  static void success({
    BuildContext? context,
    required String title,
    String? description,
    int? holdDuration,
  }) {
    show(
      context: context,
      title: title,
      description: description,
      appToastType: AppToastType.success,
      holdDuration: holdDuration,
    );
  }

  /// Convenience method for error toast
  static void error({
    BuildContext? context,
    required String title,
    String? description,
    int? holdDuration,
  }) {
    show(
      context: context,
      title: title,
      description: description,
      appToastType: AppToastType.error,
      holdDuration: holdDuration,
    );
  }

  /// Convenience method for warning toast
  static void warning({
    BuildContext? context,
    required String title,
    String? description,
    int? holdDuration,
  }) {
    show(
      context: context,
      title: title,
      description: description,
      appToastType: AppToastType.warning,
      holdDuration: holdDuration,
    );
  }

  /// Convenience method for info toast
  static void info({
    BuildContext? context,
    required String title,
    String? description,
    int? holdDuration,
  }) {
    show(
      context: context,
      title: title,
      description: description,
      appToastType: AppToastType.info,
      holdDuration: holdDuration,
    );
  }
}

/// Plays one decaying horizontal shake on first build when [active], with a
/// light haptic. Used when a duplicate toast refreshes the one already on
/// screen. Skipped entirely when the platform asks for reduced motion.
class _ShakeOnAppear extends StatefulWidget {
  const _ShakeOnAppear({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_ShakeOnAppear> createState() => _ShakeOnAppearState();
}

class _ShakeOnAppearState extends State<_ShakeOnAppear>
    with SingleTickerProviderStateMixin {
  static const int _cycles = 3;
  static const double _amplitude = 8;

  // Created only when a shake actually plays, so inactive toasts never
  // allocate a ticker.
  AnimationController? _controller;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.active) return;
    _started = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    HapticFeedback.lightImpact();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final t = controller.value;
        final dx = math.sin(t * math.pi * 2 * _cycles) * _amplitude * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}
