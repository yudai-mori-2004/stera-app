import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/home/data/enums/current_page.dart";
import "package:stera/src/modules/home/providers/navigation_provider.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/upload/ui/widgets/connect_to_wifi_bottomsheet.dart";
import "package:stera/src/modules/upload_estimate/ui/upload_estimate_bottomsheet.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/network_info_service/network_info_service.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class UploadActions extends StatefulWidget {
  const UploadActions({super.key});

  @override
  State<UploadActions> createState() => _UploadActionsState();
}

class _UploadActionsState extends State<UploadActions> {
  final ValueNotifier<bool> _storageCheckLoading = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _storageCheckLoading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<UploadProvider, AuthProvider>(
      builder: (consumerContext, up, auth, _) {
        final hasSelection = up.selection.hasSelection;
        final canSubmit = auth.user != null;
        final hasNotStartedVideos = up.allUploads.any(
          (u) => u.status == UploadStatus.notStarted,
        );
        final recordBusy = up.loading || up.picker.loading;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
          ).copyWith(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey("record-button"),
                  type: (canSubmit && hasNotStartedVideos)
                      ? ButtonType.secondary
                      : ButtonType.primary,
                  text: "Record",
                  isDisabled: recordBusy,
                  isLoading: up.picker.loading,
                  onPressed: recordBusy
                      ? null
                      : () async {
                          await up.picker.recordVideosForUpload(
                            context,
                            up.selection,
                          );
                        },
                ),
              ),
              if (canSubmit && hasNotStartedVideos) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _storageCheckLoading,
                    builder: (context, isStorageChecking, _) {
                      final isSubmitLoading = up.loading || isStorageChecking;
                      final submitEnabled =
                          hasSelection &&
                          !isSubmitLoading &&
                          !recordBusy &&
                          canSubmit;
                      return AppButton(
                        key: const ValueKey("submit-button"),
                        isDisabled: !submitEnabled,
                        type: ButtonType.primary,
                        isLoading: isSubmitLoading,
                        text: hasSelection
                            ? "Submit (${up.selection.selectionCount})"
                            : "Submit",
                        onPressed: submitEnabled
                            ? () async {
                                _storageCheckLoading.value = true;
                                try {
                                  final auth = consumerContext
                                      .read<AuthProvider>();
                                  final np = consumerContext
                                      .read<NavigationProvider>();

                                  final onWifi = await NetworkInfoService
                                      .instance
                                      .isOnWifi();
                                  if (!onWifi) {
                                    if (!consumerContext.mounted) return;
                                    final proceed =
                                        await ConnectToWifiBottomSheet.show(
                                          consumerContext,
                                        );
                                    if (!proceed) {
                                      return;
                                    }
                                    if (!consumerContext.mounted) return;
                                  }

                                  await auth.forceRefreshUser();

                                  // Capture the total size before starting, as
                                  // the selection is cleared once uploads begin.
                                  final totalBytes = up.selectedUploads
                                      .fold<int>(
                                        0,
                                        (sum, u) => sum + (u.filesize ?? 0),
                                      );

                                  final error = await up.startUploads();

                                  if (!consumerContext.mounted) return;

                                  if (error != null) {
                                    AppToast.show(
                                      title: error.message,
                                      appToastType: AppToastType.error,
                                    );
                                    return;
                                  }

                                  np.setCurrentPage(CurrentPage.home);

                                  // Now that the upload is running, show an
                                  // approximate time to completion. Keeping the
                                  // screen awake is offered inline on the
                                  // progress UI rather than as a separate step.
                                  if (!consumerContext.mounted) return;
                                  await UploadEstimateBottomSheet.show(
                                    consumerContext,
                                    totalBytes: totalBytes,
                                    onWifi: onWifi,
                                  );
                                } finally {
                                  // Starting the upload navigates away (home /
                                  // keep-awake), which disposes this State and
                                  // its notifier — writing it then throws
                                  // "used after dispose". Skip if unmounted.
                                  if (mounted) {
                                    _storageCheckLoading.value = false;
                                  }
                                }
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
