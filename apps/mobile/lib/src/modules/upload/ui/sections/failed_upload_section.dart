import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_popup_menu/app_popup_menu.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/common/widgets/section_header.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload/ui/widgets/cancel_all_uploads_confirmation_dialog.dart";
import "package:stera/src/modules/upload/ui/widgets/delete_all_uploads_confirmation_dialog.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_file_tile/upload_file_tile.dart";
import "package:stera/src/modules/upload_estimate/ui/upload_estimate_bottomsheet.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/network_info_service/network_info_service.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class FailedUploadSection extends StatelessWidget {
  const FailedUploadSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<UploadProvider, _FailedVideosData>(
      selector: (_, up) {
        // Filter directly from uploadsMap to avoid expensive allUploads sorting
        final uploadIds = up.uploadsMap.values
            .where((u) => u.status == UploadStatus.failed)
            .map((u) => u.id)
            .toList();

        return _FailedVideosData(uploadIds: uploadIds, count: uploadIds.length);
      },
      shouldRebuild: (prev, next) {
        // Only rebuild if the list of IDs changed
        if (prev.count != next.count) return true;
        // Compare IDs to see if they changed (count already checked length)
        for (int i = 0; i < prev.uploadIds.length; i++) {
          if (prev.uploadIds[i] != next.uploadIds[i]) return true;
        }
        return false;
      },
      builder: (context, data, _) {
        if (data.uploadIds.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: SectionHeader(
                      title: "Failed Uploads",
                      subtitle: "Retry to finish from where they stopped.",
                      number: data.count,
                      isError: true,
                      maxSubtitleLines: 2,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RetryAllButton(count: data.count),
                      const SizedBox(width: AppSpacing.sm),
                      const _FailedOverflowMenu(),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 150,
              child: ListView.builder(
                shrinkWrap: true,
                scrollDirection: Axis.horizontal,
                itemCount: data.uploadIds.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: index == AppSpacing.none ? AppSpacing.lg : AppSpacing.none,
                      right: AppSpacing.lg,
                    ),
                    child: SizedBox(
                      width: 150,
                      child: UploadFileTile(uploadId: data.uploadIds[index]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

class _RetryAllButton extends StatefulWidget {
  final int count;
  const _RetryAllButton({required this.count});

  @override
  State<_RetryAllButton> createState() => _RetryAllButtonState();
}

class _RetryAllButtonState extends State<_RetryAllButton> {
  bool _isRetrying = false;

  Future<void> _retryAll() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      final up = context.read<UploadProvider>();

      // Base the estimate on the bytes still left to upload, since retries
      // resume from where each file left off rather than restarting.
      final remainingBytes = up.uploadsMap.values
          .where((u) => u.status == UploadStatus.failed)
          .fold<int>(0, (sum, u) {
            final size = u.filesize ?? 0;
            final pct = (u.progress ?? 0).clamp(0, 100);
            return sum + (size * (100 - pct) ~/ 100);
          });

      final onWifi = await NetworkInfoService.instance.isOnWifi();

      await up.queueManager.retryAllFailed();

      if (!mounted) return;
      await UploadEstimateBottomSheet.show(
        context,
        totalBytes: remainingBytes,
        onWifi: onWifi,
      );
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      pressedScale: 0.9,
      onTap: _retryAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xsPlus),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          color: context.colors.textDestructive.withValues(alpha: 0.1),
        ),
        child: _isRetrying
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.textDestructive,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    size: 14,
                    color: context.colors.textDestructive,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    widget.count == 1 ? "Retry" : "Retry All",
                    style: context.textTheme.bodyXs.copyWith(
                      color: context.colors.textDestructive,
                      fontWeight: AppType.semibold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Overflow menu for bulk actions on the failed uploads: cancel all (reset to
/// ready-to-upload, keep files) or delete all (remove + delete local files).
/// Complements the per-tile ⋮ menu and the "Retry All" button.
class _FailedOverflowMenu extends StatelessWidget {
  const _FailedOverflowMenu();

  Future<void> _cancelAll(BuildContext context) async {
    final up = context.read<UploadProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CancelAllUploadsConfirmationDialog(),
    );
    if (confirmed != true) return;
    await up.queueManager.cancelAllFailed();
  }

  Future<void> _deleteAll(BuildContext context) async {
    final up = context.read<UploadProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteAllUploadsConfirmationDialog(),
    );
    if (confirmed != true) return;
    await up.queueManager.deleteAllFailed();
  }

  @override
  Widget build(BuildContext context) {
    return AppPopupMenu(
      offset: const Offset(0, 4),
      items: [
        AppPopupMenuItem(
          label: "Cancel all",
          onSelected: () => _cancelAll(context),
        ),
        AppPopupMenuItem(
          label: "Delete all",
          isDestructive: true,
          onSelected: () => _deleteAll(context),
        ),
      ],
      child: Container(
        width: 28,
        height: 28,
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          color: context.colors.textDestructive.withValues(alpha: 0.1),
        ),
        child: Icon(
          Icons.more_horiz,
          size: 16,
          color: context.colors.textDestructive,
        ),
      ),
    );
  }
}

/// Immutable data class for failed videos to ensure proper equality checks
@immutable
class _FailedVideosData {
  const _FailedVideosData({required this.uploadIds, required this.count});

  final List<int> uploadIds;
  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FailedVideosData &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          _listEquals(uploadIds, other.uploadIds);

  @override
  int get hashCode => Object.hash(count, uploadIds);

  /// Helper function to compare lists efficiently
  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
