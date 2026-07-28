import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/uploaded_videos/data/uploaded_videos_status.dart";
import "package:stera/src/modules/uploaded_videos/ui/widgets/uploaded_video_tile.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:flutter/cupertino.dart";
import "package:provider/provider.dart";

class UploadedVideosGrid extends StatefulWidget {
  /// When true (default), fills remaining height in a [Column] and scrolls
  /// internally. When false, shrink-wraps for use inside a parent scroll view
  /// (e.g. [UploadPage]).
  const UploadedVideosGrid({super.key, this.expand = true});

  final bool expand;

  @override
  State<UploadedVideosGrid> createState() => _UploadedVideosGridState();
}

class _UploadedVideosGridState extends State<UploadedVideosGrid> {
  final ScrollController scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content(UploadedVideosProvider uvp) {
      final isEmpty = uvp.filteredVideos.isEmpty;

      if (isEmpty && uvp.loading) {
        return Center(
          child: CupertinoActivityIndicator(color: context.colors.textPrimary),
        );
      }

      if (isEmpty) {
        return Center(
          child: Text(
            "No videos uploaded",
            style: context.textTheme.bodySm.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        );
      }

      return ListView.separated(
        controller: scrollController,
        shrinkWrap: !widget.expand,
        physics: widget.expand ? null : const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        itemCount: uvp.filteredVideos.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          return UploadedVideoTile(
            video: uvp.filteredVideos[index],
            showStatusBadge: uvp.selectedStatus == UploadedVideosStatus.all,
          );
        },
      );
    }

    return Consumer<UploadedVideosProvider>(
      builder: (_, uvp, _) {
        final child = content(uvp);
        if (widget.expand) {
          return Expanded(child: child);
        }
        return child;
      },
    );
  }
}
