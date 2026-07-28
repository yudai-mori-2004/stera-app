import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class ConnectToWifiBottomSheet extends StatelessWidget {
  const ConnectToWifiBottomSheet({super.key});

  /// Returns `true` if the user chose to upload anyway, `false` otherwise
  /// (cancelled, dismissed, or chose to wait for wifi).
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => const ConnectToWifiBottomSheet(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        color: context.colors.surfacePrimary,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      color: context.colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(
                      "You're not on Wi-Fi",
                      style: context.textTheme.head2Xl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lgPlus),
              Text(
                "Uploading without Wi-Fi may use a lot of cellular data and could be slower or less reliable.",
                style: context.textTheme.bodyMd.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Recommended: at least 60 Mbps upload speed for smooth, uninterrupted uploads.",
                style: context.textTheme.bodyMd.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                text: "Upload anyway",
                type: ButtonType.primary,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Pressable(
                  pressedScale: 0.9,
                  onTap: () => Navigator.of(context).pop(false),
                  child: Text(
                    "Wait for Wi-Fi",
                    style: context.textTheme.bodyMd.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
