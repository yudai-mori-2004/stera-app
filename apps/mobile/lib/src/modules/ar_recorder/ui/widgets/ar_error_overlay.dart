import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

class ArErrorOverlay extends StatelessWidget {
  const ArErrorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final errorMessage = context.select<ArRecorderProvider, String?>(
      (arp) => arp.errorMessage,
    );
    final arp = context.read<ArRecorderProvider>();

    return Container(
      color: context.darkColors.surfaceBlack.withValues(alpha: 0.87),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: context.darkColors.red, size: 48),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "Error",
              style: context.darkTextTheme.headXl.copyWith(
                color: context.darkColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              errorMessage ?? "An error occurred",
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.darkTextTheme.bodyMd.copyWith(
                color: context.darkColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if ((errorMessage ?? "").contains("Camera permission"))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppButton(
                  text: "Open Settings",
                  type: ButtonType.secondary,
                  borderColor: context.darkColors.borderDefault,
                  onPressed: () {
                    arp.openPermissionSettings();
                  },
                ),
              ),
            AppButton(
              text: "Retry",
              type: ButtonType.primary,
              onPressed: () {
                arp.initializeSession();
              },
            ),
          ],
        ),
      ),
    );
  }
}
