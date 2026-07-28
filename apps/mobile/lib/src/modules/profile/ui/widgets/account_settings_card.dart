import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/modules/profile/ui/widgets/account_settings_bottomsheet.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class AccountSettingsCard extends StatelessWidget {
  const AccountSettingsCard({super.key});

  void _showAccountSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => const AccountSettingsBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      pressedScale: 0.97,
      onTap: () => _showAccountSettingsBottomSheet(context),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        padding: const EdgeInsets.all(AppSpacing.lgPlus),
        decoration: BoxDecoration(
          color: context.colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: [
            BoxShadow(
              color: context.colors.textPrimary.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Account Settings",
                    style: context.textTheme.headMd.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "Manage your account and logout",
                    style: context.textTheme.bodySm.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Icon(
              Icons.settings_outlined,
              color: context.colors.textPrimary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
