import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_popup_menu/app_popup_menu.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/common/widgets/video_thumbnail/video_thumbnail.dart";
import "package:stera/src/modules/mcap_preview/ui/mcap_preview_page.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload/ui/widgets/cancel_queued_upload_confirmation_dialog.dart";
import "package:stera/src/modules/upload/ui/widgets/remove_queued_upload_confirmation_dialog.dart";
import "package:stera/src/services/db/db.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/upload_service/utils/resolve_file_path.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class UploadFileTileThumbnailPlaceholder extends StatelessWidget {
  final Upload upload;
  final String? thumbnailPath;
  final int? durationMs;
  final bool isSelected;
  final bool showActionsMenu;

  const UploadFileTileThumbnailPlaceholder({
    super.key,
    required this.upload,
    this.thumbnailPath,
    this.durationMs,
    required this.isSelected,
    required this.showActionsMenu,
  });

  /// Whether this upload can be paused or resumed individually.
  bool get _showPauseResume =>
      upload.status == UploadStatus.pending ||
      upload.status == UploadStatus.uploading ||
      upload.status == UploadStatus.paused;

  bool get _canCancelUpload =>
      upload.status != UploadStatus.notStarted &&
      upload.status != UploadStatus.completed;

  bool get _canDelete => upload.status != UploadStatus.completed;

  /// Only MCAP recordings can be opened in the in-app topic previewer
  /// (imported plain videos can't).
  bool get _canPreview => upload.filepath.toLowerCase().endsWith(".mcap");

  @override
  Widget build(BuildContext context) {
    final isNotStarted = upload.status == UploadStatus.notStarted;
    final overlay = (showActionsMenu || _showPauseResume || isNotStarted)
        ? Positioned.fill(
            child: Stack(
              children: [
                if (showActionsMenu) _buildActionsMenu(context),
                if (_showPauseResume) _buildPauseResumeButton(context),
                if (isNotStarted) _buildSelectionIndicator(context),
              ],
            ),
          )
        : null;

    if (thumbnailPath == null) {
      return _buildFallbackThumbnail(context, overlay: overlay);
    }

    return FutureBuilder<String>(
      future: ResolveFilePath.resolve(thumbnailPath!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildFallbackThumbnail(context, overlay: overlay);
        }
        return VideoThumbnail(
          filePath: snapshot.data,
          durationMs: durationMs,
          overlay: overlay,
        );
      },
    );
  }

  /// A checkbox-style indicator for notStarted tiles. Visual only — the tap to
  /// toggle selection is handled by the parent [UploadFileTile]'s GestureDetector.
  Widget _buildSelectionIndicator(BuildContext context) {
    return Positioned(
      top: 6,
      left: 6,
      child: Container(
        width: 24,
        height: 24,
        decoration: ShapeDecoration(
          color: isSelected
              ? context.colors.textPrimary
              : context.colors.surfacePrimary.withValues(alpha: 0.7),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            side: BorderSide(color: context.colors.textPrimary, width: 1.5),
          ),
        ),
        child: isSelected
            ? Icon(
                Icons.check_rounded,
                size: 16,
                color: context.colors.surfacePrimary,
              )
            : null,
      ),
    );
  }

  Widget _buildPauseResumeButton(BuildContext context) {
    return Consumer<UploadProvider>(
      builder: (_, up, _) {
        final isPaused = upload.status == UploadStatus.paused;
        return Positioned(
          top: 6,
          left: 6,
          child: Pressable(
            behavior: HitTestBehavior.opaque,
            pressedScale: 0.9,
            onTap: () {
              final queueManager = up.queueManager;
              if (isPaused) {
                queueManager.resumeUpload(upload.id);
              } else {
                queueManager.pauseUpload(upload.id);
              }
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: ShapeDecoration(
                color: context.colors.surfacePrimary,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
              child: Icon(
                isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 16,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionsMenu(BuildContext context) {
    if (!_canCancelUpload && !_canDelete && !_canPreview) {
      return const SizedBox.shrink();
    }

    return Consumer<UploadProvider>(
      builder: (_, up, _) {
        return Positioned(
          top: 6,
          right: 6,
          child: AppPopupMenu(
            offset: const Offset(0, 4),
            items: [
              if (_canPreview)
                AppPopupMenuItem(
                  label: "Preview",
                  onSelected: () => _previewMcap(context),
                ),
              if (_canCancelUpload)
                AppPopupMenuItem(
                  label: "Cancel upload",
                  onSelected: () => _cancelUpload(context, up),
                ),
              if (_canDelete)
                AppPopupMenuItem(
                  label: "Delete",
                  isDestructive: true,
                  onSelected: () => _deleteUpload(context, up),
                ),
            ],
            child: Container(
              width: 24,
              height: 24,
              decoration: ShapeDecoration(
                color: context.colors.surfacePrimary,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
              child: Icon(
                Icons.more_vert,
                size: 16,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _previewMcap(BuildContext context) async {
    // Stored paths can be container-relative on iOS; resolve like the
    // thumbnail does before handing the file to the reader.
    final path = await ResolveFilePath.resolve(upload.filepath);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => McapPreviewPage(
          mcapPath: path,
          title: (upload.fileName ?? upload.filepath.split("/").last)
              .replaceAll(".mcap", ""),
        ),
      ),
    );
  }

  Future<void> _cancelUpload(BuildContext context, UploadProvider up) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const CancelQueuedUploadConfirmationDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    if (up.selection.isSelected(upload)) {
      up.selection.deselectUpload(upload);
    }
    await up.queueManager.cancelUpload(upload.id);
  }

  Future<void> _deleteUpload(BuildContext context, UploadProvider up) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const RemoveQueuedUploadConfirmationDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    if (up.selection.isSelected(upload)) {
      up.selection.deselectUpload(upload);
    }
    await up.queueManager.deleteUpload(upload);
  }

  Widget _buildFallbackThumbnail(BuildContext context, {Widget? overlay}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            color: context.colors.neutralDarkGray.withValues(alpha: 0.2),
          ),
          child: Center(
            child: Icon(
              Icons.videocam,
              color: context.colors.textSecondary,
              size: 32,
            ),
          ),
        ),
        ?overlay,
      ],
    );
  }
}
