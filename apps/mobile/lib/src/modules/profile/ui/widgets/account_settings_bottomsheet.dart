import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/dotted_line.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/profile/ui/widgets/delete_account_bottomsheet.dart";
import "package:stera/src/modules/profile/ui/widgets/logout_pending_uploads_bottomsheet.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:provider/provider.dart";

class AccountSettingsBottomSheet extends StatefulWidget {
  const AccountSettingsBottomSheet({super.key});

  @override
  State<AccountSettingsBottomSheet> createState() =>
      _AccountSettingsBottomSheetState();
}

class _AccountSettingsBottomSheetState
    extends State<AccountSettingsBottomSheet> {
  static const Set<UploadStatus> _unfinishedUploadStatuses = {
    UploadStatus.notStarted,
    UploadStatus.pending,
    UploadStatus.uploading,
    UploadStatus.failed,
  };

  final ValueNotifier<bool> _logoutLoadingNotifier = ValueNotifier<bool>(false);

  int _countUnfinishedUploads(UploadProvider uploadProvider) {
    return uploadProvider.allUploads
        .where((u) => _unfinishedUploadStatuses.contains(u.status))
        .length;
  }

  Future<void> _logoutAfterConfirmation(BuildContext context) async {
    _logoutLoadingNotifier.value = true;
    try {
      final ap = context.read<AuthProvider>();
      await ap.logout();
    } finally {
      if (mounted) {
        _logoutLoadingNotifier.value = false;
      }
    }
  }

  Future<void> _onLogoutTap(BuildContext context) async {
    if (_logoutLoadingNotifier.value) return;

    final uploadProvider = context.read<UploadProvider>();
    final unfinished = _countUnfinishedUploads(uploadProvider);

    if (unfinished > 0) {
      final goAhead = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) =>
            LogoutPendingUploadsBottomSheet(unfinishedUploadCount: unfinished),
      );
      if (!context.mounted) return;
      if (goAhead != true) return;
      return;
    }

    await _logoutAfterConfirmation(context);
  }

  @override
  void dispose() {
    _logoutLoadingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Account Settings", style: context.textTheme.head2Xl),
              const SizedBox(height: AppSpacing.xl),
              ValueListenableBuilder<bool>(
                valueListenable: _logoutLoadingNotifier,
                builder: (context, logoutLoading, _) {
                  return Pressable(
                    behavior: HitTestBehavior.opaque,
                    pressedScale: 0.97,
                    onTap: logoutLoading ? null : () => _onLogoutTap(context),
                    child: Opacity(
                      opacity: logoutLoading ? 0.5 : 1,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Logout",
                                  style: context.textTheme.headMd.copyWith(
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  "and miss out on exciting rewards",
                                  style: context.textTheme.bodySm.copyWith(
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          if (logoutLoading)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.colors.textPrimary,
                              ),
                            )
                          else
                            SvgPicture.asset(
                              AppAssets.logoutIcon,
                              width: 20,
                              height: 20,
                              colorFilter: ColorFilter.mode(
                                context.colors.textPrimary,
                                BlendMode.srcIn,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const DottedLine(),
              const SizedBox(height: AppSpacing.lg),
              Pressable(
                behavior: HitTestBehavior.opaque,
                pressedScale: 0.97,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    isDismissible: true,
                    enableDrag: true,
                    builder: (context) => const DeleteAccountBottomsheet(),
                  );
                },
                child: Row(
                  spacing: AppSpacing.sm,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Delete Account",
                            style: context.textTheme.headMd,
                          ),
                          Text(
                            "Once you delete your account, all your videos and progress are gone forever.\nWe'll miss you… but we respect your choice 💔",
                            style: context.textTheme.bodySm,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.delete_outline_rounded,
                      color: context.colors.red,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
