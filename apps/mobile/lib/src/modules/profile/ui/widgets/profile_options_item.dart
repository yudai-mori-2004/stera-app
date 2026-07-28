import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

class ProfileOptionsItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLoading;

  const ProfileOptionsItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = !isLoading;

    return Pressable(
      pressedScale: 0.97,
      onTap: canTap
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: context.textTheme.headMd),
                  Text(
                    subtitle,
                    style: context.textTheme.bodySm.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            if (isLoading)
              CupertinoActivityIndicator(
                radius: 8,
                color: context.colors.textPrimary,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: context.colors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}
