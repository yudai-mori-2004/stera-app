import "dart:io";
import "dart:math" show pi;

import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/sheet_header.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/services/kv_store/kv_store.dart";
import "package:stera/src/services/permission_service/permission_service.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class NotificationPermissionBottomSheet extends StatelessWidget {
  final VoidCallback? onDismiss;

  const NotificationPermissionBottomSheet({super.key, this.onDismiss});

  Future<void> _handleSkip() async {
    await KvStore.set(KvStoreKeys.notificationPermissionSkipped, true);
    AppRouter.pop();
    onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 20 + MediaQuery.viewInsetsOf(context).bottom;
    final canSkip = Platform.isIOS && onDismiss != null;

    return Material(
      color: context.colors.surfacePrimary,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lgPlus)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.lgPlus, AppSpacing.sm, AppSpacing.lgPlus, bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lgPlus),
              SheetHeader(
                title: "Turn on notifications",
                subtitle: Platform.isIOS
                    ? "We'll use notifications to keep you updated on upload status."
                    : "Notifications are required to upload videos. We'll use them to keep you updated on upload status.",
                onClose: canSkip ? _handleSkip : null,
              ),
              const SizedBox(height: AppSpacing.lgPlus),
              const _NotificationCard(),
              const SizedBox(height: AppSpacing.lgPlus),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: AppButton(
                  text: "Go to Settings",
                  type: ButtonType.primary,
                  showShadow: false,
                  onPressed: () => PermissionService.openSettings(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.mdPlus)),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lgPlus),
        child: Center(child: _NotificationIllustration()),
      ),
    );
  }
}

/// Bell icon, concentric rings, and radiating accent marks.
class _NotificationIllustration extends StatelessWidget {
  const _NotificationIllustration();

  @override
  Widget build(BuildContext context) {
    final rayColor = context.colors.blue;
    final ringOuter = context.colors.borderDivider;
    final ringInner = context.colors.borderDivider.withValues(alpha: 0.6);
    final bellBg = context.colors.blue;
    final dotColor = context.colors.textAlert;
    final dotBorder = context.colors.surfacePrimary;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 8; i++)
            Transform.rotate(
              angle: i * pi / 4,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xsPlus),
                  child: Container(
                    width: 3,
                    height: 9,
                    decoration: BoxDecoration(
                      color: rayColor,
                      borderRadius: BorderRadius.circular(AppRadii.hairline),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            width: 122,
            height: 122,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringOuter, width: 1.5),
            ),
          ),
          Container(
            width: 106,
            height: 106,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringInner, width: 1.25),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: bellBg, shape: BoxShape.circle),
            child: Icon(
              Icons.notifications_rounded,
              color: context.colors.neutralWhite,
              size: 30,
            ),
          ),
          Positioned(
            top: 50,
            right: 50,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: dotBorder, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
