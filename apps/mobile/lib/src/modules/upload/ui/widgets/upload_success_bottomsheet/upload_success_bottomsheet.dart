import "dart:math" show pi;

import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

class UploadSuccessBottomsheet extends StatelessWidget {
  final List<Upload> completedUploads;

  const UploadSuccessBottomsheet({super.key, required this.completedUploads});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          "Videos added successfully, ${completedUploads.length} video${completedUploads.length == 1 ? '' : 's'}",
      child: Container(
        width: context.w,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: ShapeDecoration(
          shape: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
          ),
          color: context.colors.surfaceSecondary,
        ),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xlPlus),
            children: [
              const SizedBox(height: AppSpacing.sm),
              const Center(child: _UploadSuccessIllustration()),
              const SizedBox(height: AppSpacing.xlPlus),
              Text(
                "Videos uploaded successfully 🎉",
                textAlign: TextAlign.center,
                style: context.textTheme.headMd.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: AppType.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    completedUploads.length == 1
                        ? "Your video was uploaded. You can now view it in the dashboard."
                        : "Your videos were uploaded. You can now view them in the dashboard.",
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodySm.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppButton(
                text: "Continue",
                type: ButtonType.primary,
                borderRadius: 16,
                showShadow: false,
                onPressed: () => AppRouter.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blue check, concentric rings, and radiating accent marks.
class _UploadSuccessIllustration extends StatelessWidget {
  const _UploadSuccessIllustration();

  @override
  Widget build(BuildContext context) {
    final rayColor = context.colors.green;
    final ringOuter = context.colors.borderDivider;
    final ringInner = context.colors.borderDivider.withValues(alpha: 0.6);
    final checkBg = context.colors.blue;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 8; i++)
            Transform.rotate(
              angle: i * pi / 4,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xsPlus),
                  child: Container(
                    width: 3,
                    height: 9,
                    decoration: BoxDecoration(
                      color: rayColor,
                      borderRadius: BorderRadius.circular(AppRadii.hairline),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            width: 122,
            height: 122,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringOuter, width: 1.5),
            ),
          ),
          Container(
            width: 106,
            height: 106,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringInner, width: 1.25),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: checkBg, shape: BoxShape.circle),
            child: Icon(
              Icons.check_rounded,
              color: context.colors.neutralWhite,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}
