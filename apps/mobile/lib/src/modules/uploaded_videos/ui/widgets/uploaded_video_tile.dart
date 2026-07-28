import "package:stera/src/core/common/formatters/format_date.dart";
import "package:stera/src/core/common/formatters/format_file_name.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/common/widgets/video_thumbnail/video_thumbnail.dart";
import "package:stera/src/modules/home/data/models/video_metadata.dart";
import "package:stera/src/modules/uploaded_videos/ui/widgets/uploaded_video_details_bottomsheet.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

class UploadedVideoTile extends StatelessWidget {
  final VideoMetadata video;
  final bool showStatusBadge;

  const UploadedVideoTile({
    super.key,
    required this.video,
    required this.showStatusBadge,
  });

  @override
  Widget build(BuildContext context) {
    final formattedTitle = truncateFileName(video.title, 40);
    final uploadedDate = video.createdAt.formatDate;
    final subtitle = "$uploadedDate | ${video.duration.formatDuration}";

    return Pressable(
      pressedScale: 0.97,
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => UploadedVideoDetailsBottomsheet(video: video),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smPlus),
        decoration: ShapeDecoration(
          color: context.colors.neutralLightGray,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRSuperellipse(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: VideoThumbnail(
                imageUrl: video.thumbnailUrl,
                showDuration: false,
                width: 64,
                height: 48,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formattedTitle.isEmpty ? "No description" : formattedTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySm.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: AppType.semibold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyXs.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
