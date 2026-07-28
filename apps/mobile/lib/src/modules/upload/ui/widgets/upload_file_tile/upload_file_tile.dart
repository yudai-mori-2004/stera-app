import "package:stera/src/core/common/formatters/format_file_name.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_file_tile/upload_file_tile_thumbnail_placeholder.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_file_tile/upload_file_status_badge.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/upload_service/data/typedef/upload_progress.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class UploadFileTile extends StatelessWidget {
  final int uploadId;

  const UploadFileTile({super.key, required this.uploadId});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Selector<UploadProvider, _UploadTileData>(
      selector: (_, up) {
        final upload = up.getUpload(uploadId);
        final currentProgress = up.currentProgress;
        // Only include progress if it matches this uploadId
        final relevantProgress = (currentProgress?.uploadId == uploadId)
            ? currentProgress
            : null;
        // Use direct Set.contains instead of method call for better performance
        final isSelected = upload != null
            ? up.selection.selectedIds.contains(uploadId)
            : false;

        return _UploadTileData(
          upload: upload,
          relevantProgress: relevantProgress,
          eta: relevantProgress != null ? up.currentEta : null,
          isSelected: isSelected,
        );
      },
      shouldRebuild: (prev, next) {
        // Rebuild if upload changed
        if (prev.upload != next.upload) return true;
        // Rebuild if selection state changed
        if (prev.isSelected != next.isSelected) return true;
        // Rebuild if relevant progress changed (only for this upload)
        if (prev.relevantProgress != next.relevantProgress) return true;
        // Rebuild when the live ETA ticks — the progress %% can sit on the same
        // throttled bucket while the countdown keeps changing, so without this
        // the ETA renders once and then freezes.
        if (prev.eta != next.eta) return true;
        return false;
      },
      builder: (_, data, _) {
        final upload = data.upload;

        if (upload == null) return const SizedBox.shrink();

        if (upload.isHidden) return const SizedBox.shrink();

        final isSelected = data.isSelected;
        final isFailed = upload.status == UploadStatus.failed;
        final isNotStarted = upload.status == UploadStatus.notStarted;
        final showActionsMenu = upload.status != UploadStatus.completed;

        // Calculate progress: use relevantProgress if available, otherwise use stored progress
        final progressPercent = data.relevantProgress != null
            ? data.relevantProgress!.progress
            : ((upload.progress ?? 0) * 100).toInt();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Only notStarted uploads are selectable — in-progress/completed
          // uploads can't be (de)selected for a fresh submit.
          onTap: isNotStarted
              ? () => context.read<UploadProvider>().selection.toggleSelection(
                  upload,
                )
              : null,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                side: (isNotStarted && isSelected)
                    ? BorderSide(color: colors.textPrimary, width: 2)
                    : BorderSide.none,
              ),
              color: isFailed
                  ? colors.textDestructive.withValues(alpha: 0.1)
                  : colors.neutralLightGray,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Thumbnail
                Expanded(
                  flex: 3,
                  child: UploadFileTileThumbnailPlaceholder(
                    upload: upload,
                    thumbnailPath: upload.thumnbnail,
                    durationMs: upload.durationMs,
                    isSelected: isSelected,
                    showActionsMenu: showActionsMenu,
                  ),
                ),
                // File info
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        truncateFileName(
                          (upload.fileName ?? upload.filepath.split("/").last)
                              .replaceAll(".mcap", ""),
                          25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: context.textTheme.bodyXs.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      UploadFileTileStatusBadge(
                        filesize: upload.filesize,
                        eta: upload.status == UploadStatus.uploading
                            ? data.eta
                            : null,
                      ),
                    ],
                  ),
                ),
                if (upload.status != UploadStatus.notStarted)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: LinearProgressIndicator(
                      value: progressPercent / 100,
                      color: colors.textPrimary,
                      backgroundColor: context.colors.neutralGray,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Immutable data class for upload tile to ensure proper equality checks
@immutable
class _UploadTileData {
  const _UploadTileData({
    required this.upload,
    required this.relevantProgress,
    required this.eta,
    required this.isSelected,
  });

  final Upload? upload;
  final UploadProgress? relevantProgress;
  final Duration? eta;
  final bool isSelected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _UploadTileData &&
          runtimeType == other.runtimeType &&
          upload == other.upload &&
          relevantProgress == other.relevantProgress &&
          eta == other.eta &&
          isSelected == other.isSelected;

  @override
  int get hashCode => Object.hash(upload, relevantProgress, eta, isSelected);
}
