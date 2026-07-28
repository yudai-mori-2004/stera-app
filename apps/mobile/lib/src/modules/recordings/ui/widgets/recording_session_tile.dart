import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:stera/src/core/common/formatters/format_bytes.dart";
import "package:stera/src/core/common/formatters/format_date.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_popup_menu/app_popup_menu.dart";
import "package:stera/src/core/common/widgets/video_thumbnail/video_thumbnail.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/colors.dart";
import "package:stera/src/services/recordings_service/data/models/recording_session.dart";

/// One on-device recording, as a grid tile.
///
/// Deliberately mirrors `UploadFileTile`: same rounded superellipse on
/// [C.neutralLightGray], the same 3-flex [VideoThumbnail] over a name and a
/// meta line. A recording should look the same whether or not the build can
/// upload it.
///
/// While [isFinalizing] the native writer is still closing out the mcap, so the
/// tile shows a spinner and refuses the tap: `McapReader` needs the trailing
/// magic and would otherwise open onto an empty topic list.
class RecordingSessionTile extends StatelessWidget {
  const RecordingSessionTile({
    super.key,
    required this.session,
    required this.isFinalizing,
    required this.onPreview,
    required this.onDelete,
  });

  final RecordingSession session;
  final bool isFinalizing;
  final ValueChanged<RecordingSession> onPreview;
  final ValueChanged<RecordingSession> onDelete;

  /// The tile's headline, also used as the preview page's title.
  ///
  /// `RecordingsService` falls back to epoch 0 when a directory name doesn't
  /// parse, which would otherwise render every such take as "01 Jan 1970".
  static String titleFor(RecordingSession session) =>
      session.recordedAt.millisecondsSinceEpoch == 0
      ? session.directoryName
      : session.recordedAt.formatDateTime;

  static String subtitleFor(RecordingSession session) => [
    "${session.frameCount} frames",
    formatBytes(session.sizeBytes),
  ].join(" • ");

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFinalizing ? null : () => onPreview(session),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          color: colors.neutralLightGray,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              flex: 3,
              child: VideoThumbnail(
                filePath: session.thumbnailPath,
                durationMs: (session.durationSeconds * 1000).round(),
                // The duration chip would sit under the spinner scrim and read
                // as a finished take.
                showDuration: !isFinalizing,
                overlay: isFinalizing
                    ? _FinalizingOverlay(colors: colors)
                    : _MenuOverlay(
                        onPreview: () => onPreview(session),
                        onDelete: () => onDelete(session),
                        colors: colors,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titleFor(session),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyXs.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    isFinalizing ? "Processing…" : subtitleFor(session),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyXs.copyWith(
                      color: colors.textSecondary,
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

class _FinalizingOverlay extends StatelessWidget {
  const _FinalizingOverlay({required this.colors});

  final C colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.neutralBlack.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Center(
        child: CupertinoActivityIndicator(color: colors.neutralWhite),
      ),
    );
  }
}

class _MenuOverlay extends StatelessWidget {
  const _MenuOverlay({
    required this.onPreview,
    required this.onDelete,
    required this.colors,
  });

  final VoidCallback onPreview;
  final VoidCallback onDelete;
  final C colors;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: AppPopupMenu(
        items: [
          // Duplicates the tile tap on purpose: the tap target isn't signposted,
          // and a menu whose only entry is destructive invites a mis-tap.
          AppPopupMenuItem(label: "Preview recording", onSelected: onPreview),
          AppPopupMenuItem(
            label: "Delete recording",
            isDestructive: true,
            onSelected: onDelete,
          ),
        ],
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          decoration: BoxDecoration(
            color: colors.surfacePrimary.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
          child: Icon(
            Icons.more_horiz,
            size: 18,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
