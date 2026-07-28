import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class ResumeUploadsButton extends StatelessWidget {
  const ResumeUploadsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      pressedScale: 0.97,
      onTap: () => context.read<UploadProvider>().queueManager.resumeQueue(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg).copyWith(bottom: 16),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          color: context.inverseColors.surfacePrimary,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                "Uploads paused",
                style: context.textTheme.headSm.copyWith(
                  color: context.inverseColors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: context.inverseColors.textPrimary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              "Resume all",
              style: context.textTheme.headSm.copyWith(
                color: context.inverseColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
