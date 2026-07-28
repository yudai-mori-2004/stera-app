import "package:flutter/material.dart";
import "package:solar_icons/solar_icons.dart";
import "package:stera/src/core/common/formatters/format_bytes.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/enums/interactive_list_tile_enums.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/interactive_list.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/interactive_list_tile.dart";
import "package:stera/src/core/common/widgets/section_header.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/mcap_preview/helpers/mcap_formatters.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_card.dart";
import "package:stera/src/services/mcap_reader/cdr/ros2_message_decoder.dart";
import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";

/// Topics and metadata sections for a loaded MCAP file: one tile per topic
/// (opens the player) and one per metadata record (opens the detail sheet).
class McapPreviewContent extends StatelessWidget {
  final List<McapTopicInfo> topics;
  final List<McapMetadataIndex> metadataIndexes;
  final int fileSizeBytes;
  final String? title;
  final ValueChanged<McapTopicInfo> onTopicPressed;
  final ValueChanged<McapMetadataIndex> onMetadataPressed;

  const McapPreviewContent({
    super.key,
    required this.topics,
    required this.metadataIndexes,
    required this.fileSizeBytes,
    required this.title,
    required this.onTopicPressed,
    required this.onMetadataPressed,
  });

  @override
  Widget build(BuildContext context) {
    return McapCard(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.none, AppSpacing.lg, AppSpacing.lg),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: "Topics",
              number: topics.length,
              subtitle:
                  "${title ?? "This recording"} • ${formatBytes(fileSizeBytes)}",
            ),
            const SizedBox(height: AppSpacing.md),
            InteractiveList(
              backgroundColor: context.colors.surfacePrimary,
              titleTextStyle: context.textTheme.bodyMdMedium,
              subTitleTextStyle: context.textTheme.bodyXs.copyWith(
                color: context.colors.textSecondary,
              ),
              children: [
                for (final topic in topics)
                  InteractiveListTile(
                    title: topic.topic,
                    subTitle: _topicSubtitle(topic),
                    icon: _iconFor(topic.schemaName),
                    iconState: InteractiveListTileIconState.normal,
                    leadingIconSize: 20,
                    action: InteractiveListTileAction.arrow,
                    onPressed: () => onTopicPressed(topic),
                  ),
              ],
            ),
            if (metadataIndexes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: "Metadata",
                number: metadataIndexes.length,
                subtitle: "Session info, calibrations and sync records",
              ),
              const SizedBox(height: AppSpacing.md),
              InteractiveList(
                backgroundColor: context.colors.surfacePrimary,
                titleTextStyle: context.textTheme.bodyMdMedium,
                children: [
                  for (final index in metadataIndexes)
                    InteractiveListTile(
                      title: index.name,
                      icon: Icons.data_object,
                      iconState: InteractiveListTileIconState.normal,
                      leadingIconSize: 20,
                      action: InteractiveListTileAction.arrow,
                      onPressed: () => onMetadataPressed(index),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _topicSubtitle(McapTopicInfo topic) {
    final frequency = topic.frequencyHz;
    final parts = [
      topic.schemaName.split("/").last,
      "${formatMessageCount(topic.messageCount)} msgs",
      if (frequency > 0) "${frequency.toStringAsFixed(1)} Hz",
    ];
    return parts.join(" • ");
  }

  IconData _iconFor(String schemaName) {
    switch (schemaName) {
      case Ros2MessageDecoder.compressedImageSchema:
        return SolarIconsOutline.videocameraRecord;
      case Ros2MessageDecoder.rawImageSchema:
        return Icons.layers_outlined;
      case "sensor_msgs/msg/Imu":
        return Icons.vibration;
      case "geometry_msgs/msg/PoseStamped":
      case "tf2_msgs/msg/TFMessage":
      case "nav_msgs/msg/Path":
        return Icons.route_outlined;
      case "sensor_msgs/msg/PointCloud2":
      case "visualization_msgs/msg/Marker":
        return Icons.grain;
      case "sensor_msgs/msg/NavSatFix":
        return Icons.gps_fixed;
      case "sensor_msgs/msg/CameraInfo":
        return SolarIconsOutline.cameraMinimalistic;
      default:
        return Icons.list_alt_outlined;
    }
  }
}
