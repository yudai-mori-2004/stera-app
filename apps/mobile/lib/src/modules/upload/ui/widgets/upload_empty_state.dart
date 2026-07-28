import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:solar_icons/solar_icons.dart";

class UploadEmptyState extends StatelessWidget {
  const UploadEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lgPlus),
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        color: context.colors.surfaceSecondary,
      ),
      child: Row(
        children: [
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Image.asset(
              AppAssets.surprisedStatue,
              width: 60,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Nothing in queue", style: context.textTheme.headMd),
                const SizedBox(height: AppSpacing.xs),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: "Record videos from the ",
                        style: context.textTheme.bodySm.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                          child: Icon(
                            SolarIconsOutline.uploadSquare,
                            size: 16,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
                      TextSpan(
                        text: " tab to start uploading",
                        style: context.textTheme.bodySm.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
