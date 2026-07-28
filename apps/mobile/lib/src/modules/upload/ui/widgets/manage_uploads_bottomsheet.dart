import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/dotted_line.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/upload/ui/widgets/cancel_all_uploads_confirmation_dialog.dart";
import "package:stera/src/modules/upload/ui/widgets/delete_all_uploads_confirmation_dialog.dart";
import "package:stera/src/modules/profile/ui/widgets/profile_options_item.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

/// All-uploads controls, mirroring the per-upload tile actions:
/// pause/resume all, cancel all (reset to ready-to-upload, keep files), and
/// delete all (remove + delete local files).
class ManageUploadsBottomSheet extends StatefulWidget {
  const ManageUploadsBottomSheet({super.key});

  @override
  State<ManageUploadsBottomSheet> createState() =>
      _ManageUploadsBottomSheetState();
}

class _ManageUploadsBottomSheetState extends State<ManageUploadsBottomSheet> {
  final ValueNotifier<bool> _isTogglingPause = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isCancelling = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isDeleting = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isTogglingPause.dispose();
    _isCancelling.dispose();
    _isDeleting.dispose();
    super.dispose();
  }

  Future<void> _togglePause() async {
    _isTogglingPause.value = true;
    try {
      final queueManager = context.read<UploadProvider>().queueManager;
      if (queueManager.isPaused) {
        await queueManager.resumeQueue();
      } else {
        await queueManager.pauseQueue();
      }
    } finally {
      if (mounted) _isTogglingPause.value = false;
    }
  }

  Future<void> _cancelAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CancelAllUploadsConfirmationDialog(),
    );
    if (confirmed != true || !mounted) return;

    _isCancelling.value = true;
    try {
      await context.read<UploadProvider>().queueManager.cancelAllToNotStarted();
      if (mounted) AppRouter.pop();
    } finally {
      if (mounted) _isCancelling.value = false;
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteAllUploadsConfirmationDialog(),
    );
    if (confirmed != true || !mounted) return;

    _isDeleting.value = true;
    try {
      await context.read<UploadProvider>().queueManager.cancelAll();
      if (mounted) AppRouter.pop();
    } finally {
      if (mounted) _isDeleting.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<UploadProvider, bool>(
      selector: (_, up) => up.queueManager.isPaused,
      builder: (context, isPaused, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lgPlus, vertical: AppSpacing.xxl),
          width: context.w,
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            color: context.colors.surfacePrimary,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Manage uploads", style: context.textTheme.headLg),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  color: context.colors.surfaceSecondary,
                ),
                child: Column(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: _isTogglingPause,
                      builder: (context, isToggling, _) {
                        return ProfileOptionsItem(
                          title: isPaused
                              ? "Resume all uploads"
                              : "Pause all uploads",
                          subtitle: isPaused
                              ? "Pick up every upload from where it left off."
                              : "Stop all uploads for now — each one resumes "
                                    "from where it left off.",
                          onTap: _togglePause,
                          isLoading: isToggling,
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    DottedLine(color: context.colors.textTertiary),
                    const SizedBox(height: AppSpacing.lg),
                    ValueListenableBuilder<bool>(
                      valueListenable: _isCancelling,
                      builder: (context, isCancelling, _) {
                        return ProfileOptionsItem(
                          title: "Cancel all uploads",
                          subtitle:
                              "Stop uploading and move every video back to "
                              "ready-to-upload. Local recordings stay.",
                          onTap: _cancelAll,
                          isLoading: isCancelling,
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    DottedLine(color: context.colors.textTertiary),
                    const SizedBox(height: AppSpacing.lg),
                    ValueListenableBuilder<bool>(
                      valueListenable: _isDeleting,
                      builder: (context, isDeleting, _) {
                        return ProfileOptionsItem(
                          title: "Delete all videos",
                          subtitle:
                              "Remove every video and delete the local "
                              "recordings. This can't be undone.",
                          onTap: _deleteAll,
                          isLoading: isDeleting,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }
}
