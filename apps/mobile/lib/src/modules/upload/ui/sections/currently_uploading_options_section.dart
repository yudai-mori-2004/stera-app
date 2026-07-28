import "package:stera/src/core/common/widgets/dotted_line.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/common/widgets/section_header.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload/ui/widgets/manage_uploads_bottomsheet.dart";
import "package:stera/src/modules/upload/ui/widgets/resume_uploads_button.dart";
import "package:stera/src/modules/upload/ui/widgets/upload_file_tile/upload_file_tile.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class CurrentlyUploadingSection extends StatelessWidget {
  const CurrentlyUploadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<UploadProvider, _UploadingVideosData>(
      selector: (_, up) {
        // Filter directly from uploadsMap to avoid expensive allUploads sorting
        final active = up.uploadsMap.values
            .where(
              (u) =>
                  u.status == UploadStatus.uploading ||
                  u.status == UploadStatus.pending ||
                  u.status == UploadStatus.paused,
            )
            .toList();

        return _UploadingVideosData(
          uploadIds: active.map((u) => u.id).toList(),
          count: active.length,
          uploadingCount: active
              .where((u) => u.status == UploadStatus.uploading)
              .length,
          queuedCount: active
              .where((u) => u.status == UploadStatus.pending)
              .length,
          pausedCount: active
              .where((u) => u.status == UploadStatus.paused)
              .length,
          isPaused: up.queueManager.isPaused,
        );
      },
      shouldRebuild: (prev, next) {
        // Rebuild if pause state changed
        if (prev.isPaused != next.isPaused) return true;
        // Rebuild if the status breakdown changed
        if (prev.uploadingCount != next.uploadingCount ||
            prev.queuedCount != next.queuedCount ||
            prev.pausedCount != next.pausedCount) {
          return true;
        }
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
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SectionHeader(
                    title: "Currently Uploading",
                    subtitle: data.statusBreakdown,
                    number: data.count,
                  ),
                  // All-uploads controls (pause-all / cancel-all). Per-upload
                  // pause/resume/cancel live on each tile's overlay.
                  _ManageButton(isPaused: data.isPaused),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (data.isPaused) const ResumeUploadsButton(),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
              child: DottedLine(),
            ),
          ],
        );
      },
    );
  }
}

/// Subtle entry point to the all-uploads controls (pause / resume / cancel
/// everything). Reflects the queue's paused state in its icon.
class _ManageButton extends StatelessWidget {
  const _ManageButton({required this.isPaused});

  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      behavior: HitTestBehavior.opaque,
      pressedScale: 0.9,
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const ManageUploadsBottomSheet(),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xsPlus),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.tune_rounded,
              size: 14,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              "Manage",
              style: context.textTheme.bodyXs.copyWith(
                color: context.colors.textSecondary,
                fontWeight: AppType.semibold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Immutable data class for uploading videos to ensure proper equality checks
@immutable
class _UploadingVideosData {
  const _UploadingVideosData({
    required this.uploadIds,
    required this.count,
    required this.uploadingCount,
    required this.queuedCount,
    required this.pausedCount,
    required this.isPaused,
  });

  final List<int> uploadIds;
  final int count;
  final int uploadingCount;
  final int queuedCount;
  final int pausedCount;
  final bool isPaused;

  /// e.g. "1 uploading · 2 queued · 1 paused" — only non-zero parts shown.
  String get statusBreakdown {
    final parts = <String>[
      if (uploadingCount > 0) "$uploadingCount uploading",
      if (queuedCount > 0) "$queuedCount queued",
      if (pausedCount > 0) "$pausedCount paused",
    ];
    if (parts.isEmpty) return "Your videos are currently being uploaded";
    return parts.join(" · ");
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _UploadingVideosData &&
          runtimeType == other.runtimeType &&
          count == other.count &&
          uploadingCount == other.uploadingCount &&
          queuedCount == other.queuedCount &&
          pausedCount == other.pausedCount &&
          isPaused == other.isPaused &&
          _listEquals(uploadIds, other.uploadIds);

  @override
  int get hashCode => Object.hash(
    count,
    uploadIds,
    uploadingCount,
    queuedCount,
    pausedCount,
    isPaused,
  );

  /// Helper function to compare lists efficiently
  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
