import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

/// Shown before logout when there are uploads that are not finished (local queue).
class LogoutPendingUploadsBottomSheet extends StatefulWidget {
  const LogoutPendingUploadsBottomSheet({
    super.key,
    required this.unfinishedUploadCount,
  });

  final int unfinishedUploadCount;

  @override
  State<LogoutPendingUploadsBottomSheet> createState() =>
      _LogoutPendingUploadsBottomSheetState();
}

class _LogoutPendingUploadsBottomSheetState
    extends State<LogoutPendingUploadsBottomSheet> {
  final ValueNotifier<bool> _loggingOutNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _loggingOutNotifier.dispose();
    super.dispose();
  }

  Future<void> _onLogoutAnyway() async {
    if (_loggingOutNotifier.value) return;
    _loggingOutNotifier.value = true;
    try {
      final ap = context.read<AuthProvider>();
      await ap.logout();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        _loggingOutNotifier.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.unfinishedUploadCount;
    final summary = n == 1
        ? "You have 1 video in your upload queue that is not finished yet."
        : "You have $n videos in your upload queue that are not finished yet.";

    return ValueListenableBuilder<bool>(
      valueListenable: _loggingOutNotifier,
      builder: (context, loggingOut, _) {
        return PopScope(
          canPop: !loggingOut,
          child: Container(
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              color: context.colors.surfacePrimary,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Finish uploads first?",
                      style: context.textTheme.head2Xl,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      "$summary Logging out will remove this upload data from this device, and you may need to add your videos again later.",
                      style: context.textTheme.bodySm.copyWith(
                        color: context.colors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      text: "Log out anyway",
                      type: ButtonType.primary,
                      isLoading: loggingOut,
                      isDisabled: loggingOut,
                      onPressed: _onLogoutAnyway,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      text: "Cancel",
                      type: ButtonType.secondary,
                      isDisabled: loggingOut,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
