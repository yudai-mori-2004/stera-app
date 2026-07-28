import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/formatters/format_date.dart";
import "package:stera/src/modules/uploaded_videos/data/uploaded_videos_status.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:solar_icons/solar_icons.dart";

class UploadedVideosHeader extends StatelessWidget {
  const UploadedVideosHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadedVideosProvider>(
      builder: (_, uvp, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  uvp.selectedStatus.title,
                  style: context.textTheme.headMd,
                ),
              ),
              if (uvp.filteredVideos.isNotEmpty)
                Row(
                  children: [
                    Text(
                      uvp.filteredVideos.length.toString(),
                      style: context.textTheme.headMd,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 2,
                      height: 16,
                      decoration: BoxDecoration(
                        color: context.colors.neutralLightGray,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      SolarIconsOutline.clockCircle,
                      size: 16,
                      color: context.colors.iconPrimary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      uvp.filteredVideos
                          .map((e) => e.duration)
                          .fold<int>(0, (prev, curr) => prev + curr)
                          .formatDuration,
                      style: context.textTheme.headMd,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
