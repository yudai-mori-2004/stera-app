import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/modules/upload/helpers/upload_utils.dart";
import "package:stera/src/modules/upload_estimate/helpers/upload_estimate_format.dart";
import "package:stera/src/modules/upload_estimate/services/upload_speed_tracker.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

/// Shown right after an upload starts to give the user an approximate time to
/// completion, based on the total size of the files and the user's measured
/// upload speed (falling back to a generic assumption before any history
/// exists). The underlying speed is intentionally not surfaced in the UI.
class UploadEstimateBottomSheet extends StatelessWidget {
  const UploadEstimateBottomSheet({
    super.key,
    required this.totalBytes,
    required this.estimate,
  });

  final int totalBytes;
  final UploadTimeEstimate estimate;

  /// Displays the estimate. Returns true when the user taps "Keep screen
  /// awake" — the caller is responsible for navigating to the keep-awake
  /// screen, so this module stays free of upload-module dependencies.
  ///
  /// Temporarily disabled — flip [_enabled] to restore the post-start sheet.
  static const bool _enabled = false;

  static Future<bool> show(
    BuildContext context, {
    required int totalBytes,
    required bool onWifi,
  }) async {
    if (!_enabled) return false;

    final estimate = UploadSpeedTracker.estimate(
      totalBytes: totalBytes,
      onWifi: onWifi,
    );
    final keepAwake = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (context) =>
          UploadEstimateBottomSheet(totalBytes: totalBytes, estimate: estimate),
    );
    return keepAwake ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final sizeLabel = formatFileSize(totalBytes);
    final bottomPad = 24 + MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: context.colors.surfaceSecondary,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.lgPlus),
              decoration: BoxDecoration(
                color: context.colors.borderDivider,
                borderRadius: BorderRadius.circular(AppRadii.hairline),
              ),
            ),
            Text(
              "Upload started",
              textAlign: TextAlign.center,
              style: context.textTheme.headMd.copyWith(
                color: context.colors.textPrimary,
                fontWeight: AppType.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Sending $sizeLabel to the cloud",
              textAlign: TextAlign.center,
              style: context.textTheme.bodySm.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _EstimateStatCard(etaLabel: formatEta(estimate.duration)),
            const SizedBox(height: AppSpacing.lg),
            const _KeepAwakeTip(),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              text: "Keep screen awake",
              type: ButtonType.primary,
              borderRadius: 16,
              showShadow: false,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Pressable(
                onTap: () => Navigator.of(context).pop(false),
                behavior: HitTestBehavior.opaque,
                pressedScale: 0.9,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    "Continue",
                    style: context.textTheme.bodyMd.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstimateStatCard extends StatelessWidget {
  const _EstimateStatCard({required this.etaLabel});

  final String etaLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lgPlus, vertical: AppSpacing.lgPlus),
      decoration: BoxDecoration(
        color: context.colors.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: context.colors.borderDivider.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        children: [
          Text(
            "Estimated time remaining",
            style: context.textTheme.bodySm.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xsPlus),
          Text(
            etaLabel,
            textAlign: TextAlign.center,
            style: context.textTheme.headLg.copyWith(
              color: context.colors.textPrimary,
              fontWeight: AppType.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeepAwakeTip extends StatelessWidget {
  const _KeepAwakeTip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdPlus, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.mdPlus),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.brightness_high_outlined,
            size: 18,
            color: context.colors.green,
          ),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
            child: Text(
              "Uploads finish fastest with the app open. Keep-awake mode "
              "stops your screen from sleeping.",
              style: context.textTheme.bodySm.copyWith(
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
