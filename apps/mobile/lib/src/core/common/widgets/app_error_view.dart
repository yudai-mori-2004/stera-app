import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:stera/src/core/theme/colors.dart";

/// Replaces Flutter's default error box (red in debug, grey in release) when a
/// widget fails to build.
///
/// Release builds show only a neutral apology — an exception string tells a user
/// nothing and can leak internals. Debug builds keep the details inline, and
/// either way a long-press copies the full error so it can be pasted into a bug
/// report.
class AppErrorView extends StatefulWidget {
  const AppErrorView({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  State<AppErrorView> createState() => _AppErrorViewState();
}

class _AppErrorViewState extends State<AppErrorView> {
  static const Duration _confirmationDuration = Duration(milliseconds: 2600);

  Timer? _resetTimer;
  bool _copied = false;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  /// The stack is the half worth having in a bug report — the exception alone
  /// rarely says where it came from.
  String get _copyText {
    final exception = widget.details.exceptionAsString();
    final stack = widget.details.stack;
    return stack == null ? exception : "$exception\n\n$stack";
  }

  Future<void> _copy() async {
    // Fires first: the clipboard write is async and the toast may never
    // arrive, so the haptic is the one confirmation that always lands.
    await HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: _copyText));
    if (!mounted) return;

    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(_confirmationDuration, () {
      if (mounted) setState(() => _copied = false);
    });

    _showToast();
  }

  /// Best-effort. The toast renders in the app's navigator overlay, which only
  /// exists when the failure was contained to part of the tree — if the shell
  /// itself is what broke, there is nothing to host it. The in-view swap above
  /// is the confirmation that survives either way.
  void _showToast() {
    if (AppToast.navigatorKey?.currentState?.overlay == null) return;
    try {
      AppToast.info(title: "Error details copied");
    } catch (_) {
      // A failed toast must never escalate into a second error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.details.exceptionAsString();

    // No Scaffold/Theme is guaranteed here — this can replace any widget
    // anywhere in the tree — so everything is drawn from primitives. The
    // colours still come from the palette rather than from literals: `C.dark()`
    // is a plain constructor, so it needs no ancestor, and it keeps this screen
    // following the brand like every other one.
    final colors = C.dark();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _copy,
        child: ColoredBox(
          color: colors.surfacePrimary,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _copied
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    color: _copied ? colors.green : colors.yellow,
                    size: 28,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Something went wrong here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.neutralWhite, fontSize: AppType.md),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textDestructive,
                        fontSize: AppType.sm,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _copied ? "Copied to clipboard" : "Long-press to copy details",
                    style: TextStyle(
                      color: _copied
                          ? colors.green
                          : colors.neutralWhite.withValues(alpha: 0.6),
                      fontSize: AppType.sm,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
