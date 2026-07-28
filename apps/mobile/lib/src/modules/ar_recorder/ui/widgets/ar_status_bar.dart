import "dart:async";

import "package:stera/src/core/common/formatters/format_date.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/ar_recorder/ui/extensions/ar_tracking_state_color.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/exit_ar_recorder_warning_dialog.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

class ArStatusBar extends StatelessWidget {
  const ArStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isRecording = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isRecording,
    );
    final isPaused = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isPaused,
    );
    final showSessionChrome = isRecording || isPaused;
    final trackingState = context.select<ArRecorderProvider, ArTrackingState>(
      (arp) => arp.trackingState,
    );
    final recordingDuration = context.select<ArRecorderProvider, Duration>(
      (arp) => arp.recordingDuration,
    );
    final arp = context.read<ArRecorderProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.darkColors.surfaceSecondary.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: context.darkColors.borderDefault, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pressable(
            pressedScale: 0.9,
            onTap: () {
              if (showSessionChrome) {
                unawaited(_showDiscardDialog(context, arp));
              } else {
                AppRouter.pop();
              }
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.darkColors.textSecondary.withValues(alpha: 0.2),
              ),
              child: Icon(
                Icons.close,
                size: 16,
                color: context.darkColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: trackingState.color(context).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadii.xsPlus),
              border: Border.all(color: trackingState.color(context), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: trackingState.color(context),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xsPlus),
                Text(
                  trackingState.label,
                  style: context.darkTextTheme.headSm.copyWith(
                    color: trackingState.color(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (showSessionChrome) ...[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isPaused
                    ? context.darkColors.yellow
                    : context.darkColors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              recordingDuration.formatHmsWithSeconds,
              overflow: TextOverflow.ellipsis,
              style: context.darkTextTheme.bodyLg.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Future<void> _showDiscardDialog(
    BuildContext context,
    ArRecorderProvider arp,
  ) async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => const ExitArRecorderWarningDialog(),
    );
    if (shouldDiscard == true) {
      HapticFeedback.heavyImpact();
      await arp.cancelRecording();
      AppRouter.pop();
    }
  }
}
