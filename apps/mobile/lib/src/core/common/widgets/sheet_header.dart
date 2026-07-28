import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

/// Standard header for bottom sheets: a title, a supporting subtitle, and an
/// optional close button. When [onClose] is null the button is hidden.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.textTheme.headMd.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: AppType.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xsPlus),
              Text(
                subtitle,
                style: context.textTheme.bodySm.copyWith(
                  color: context.colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
              backgroundColor: context.colors.surfaceTertiary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              padding: const EdgeInsets.all(AppSpacing.smPlus),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ],
    );
  }
}
