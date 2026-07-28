import "package:stera/src/core/common/formatters/format_bytes.dart";
import "package:stera/src/core/common/formatters/format_date.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/info_row/info_row.dart";
import "package:stera/src/core/common/widgets/sheet_header.dart";
import "package:stera/src/core/common/widgets/video_thumbnail/video_thumbnail.dart";
import "package:stera/src/modules/home/data/models/video_metadata.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:solar_icons/solar_icons.dart";

class UploadedVideoDetailsBottomsheet extends StatelessWidget {
  const UploadedVideoDetailsBottomsheet({super.key, required this.video});

  final VideoMetadata video;

  String _formatFps(double? value) {
    if (value == null) return "--";
    return "${value.toStringAsFixed(2)} fps";
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.w,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: ShapeDecoration(
        color: context.colors.surfaceSecondary,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppRadii.md),
            topRight: Radius.circular(AppRadii.md),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(
            title: "Recording Details",
            subtitle: "Video resolution: ${video.resolution ?? "--"}",
            onClose: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: AppSpacing.xsPlus),
          const SizedBox(height: AppSpacing.lg),
          if (video.thumbnailUrl.isNotEmpty)
            ClipRSuperellipse(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: VideoThumbnail(
                imageUrl: video.thumbnailUrl,
                showDuration: true,
                width: context.w - 48,
                height: (context.w - 48) * 9 / 16,
                durationMs: video.duration * 1000,
              ),
            ),
          if (video.thumbnailUrl.isNotEmpty) const SizedBox(height: AppSpacing.lg),
          Container(
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              color: context.colors.neutralLightGray,
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                  icon: SolarIconsOutline.clockCircle,
                  label: "Duration",
                  value: video.duration.formatDuration,
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.borderDivider,
                ),
                InfoRow(
                  icon: SolarIconsOutline.calendarMinimalistic,
                  label: "Recorded at",
                  value: video.createdAt.formatDateTime,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              color: context.colors.neutralLightGray,
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                  icon: Icons.speed_rounded,
                  label: "RGB fps",
                  value: _formatFps(video.rgbFps),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.borderDivider,
                ),
                InfoRow(
                  icon: Icons.high_quality_rounded,
                  label: "Video resolution",
                  value: video.resolution ?? "--",
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.borderDivider,
                ),
                InfoRow(
                  icon: Icons.sd_storage_rounded,
                  label: "File size",
                  value: formatBytes(video.fileSizeBytes),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.borderDivider,
                ),
                InfoRow(
                  icon: Icons.sensors_rounded,
                  label: "IMU fps",
                  value: _formatFps(video.imuFps),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.borderDivider,
                ),
                InfoRow(
                  icon: Icons.layers_rounded,
                  label: "Depth fps",
                  value: _formatFps(video.depthFps),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.borderDivider,
                ),
                InfoRow(
                  icon: Icons.blur_on_rounded,
                  label: "Pointcloud fps",
                  value: _formatFps(video.pointcloudFps),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

