import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

/// Shown when cold-boot bootstrap throws. Offers a single retry that re-runs
/// `StartupViewModel.retryInitialization`.
class StartupErrorView extends StatelessWidget {
  const StartupErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceTertiary,
      body: Container(
        width: context.w,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(AppAssets.texture),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: context.colors.textDestructive,
                  size: 48,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  "Something went wrong",
                  style: context.textTheme.headLg,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "We couldn't start the app. Please try again.",
                  style: context.textTheme.bodyMd.copyWith(
                    color: context.colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),
                AppButton(
                  text: "Retry",
                  type: ButtonType.primary,
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
