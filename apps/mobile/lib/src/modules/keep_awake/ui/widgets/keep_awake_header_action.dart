import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/keep_awake/helpers/keep_awake_controller.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

/// App-header toggle that keeps the screen awake while uploads run, so the OS
/// doesn't sleep the screen and slow the transfer. Only shown while an upload
/// is in progress, since keeping the screen on otherwise just wastes battery.
class KeepAwakeHeaderAction extends StatelessWidget {
  const KeepAwakeHeaderAction({super.key});

  static bool _hasActiveUploads(UploadProvider up) => up.uploadsMap.values.any(
    (u) =>
        u.status == UploadStatus.pending || u.status == UploadStatus.uploading,
  );

  @override
  Widget build(BuildContext context) {
    return Selector<UploadProvider, bool>(
      selector: (_, up) => _hasActiveUploads(up),
      builder: (context, hasActiveUploads, _) {
        if (!hasActiveUploads) return const SizedBox.shrink();
        return _buildToggle(context);
      },
    );
  }

  Widget _buildToggle(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: KeepAwakeController.enabled,
      builder: (context, on, _) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Pressable(
              pressedScale: 0.9,
              onTap: () {
                KeepAwakeController.toggle();
              },
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xsPlus),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on
                      ? context.colors.textPrimary
                      : context.colors.surfacePrimary,
                  border: Border.all(color: context.colors.textPrimary),
                ),
                child: Icon(
                  on
                      ? Icons.brightness_high_rounded
                      : Icons.brightness_low_outlined,
                  size: 20,
                  color: on
                      ? context.colors.textInversePrimary
                      : context.colors.textPrimary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
