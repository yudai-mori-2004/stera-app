import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/spring_entrance.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class ArUnsupportedDeviceBottomSheet extends StatelessWidget {
  const ArUnsupportedDeviceBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SpringEntrance(
      beginOffset: Offset.zero,
      beginScale: 0.94,
      child: Container(
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          color: context.colors.surfaceSecondary,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.info, size: 60, color: context.colors.red),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    "Device Not Supported",
                    style: context.textTheme.head2Xl,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    "Uploads aren’t supported on this device. Please use a supported device.",
                    style: context.textTheme.bodySm.copyWith(
                      color: context.colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      text: "Got it!",
                      type: ButtonType.secondary,
                      height: 56,
                      showShadow: false,
                      onPressed: () => AppRouter.pop(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
