import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconSize = 20,
  });

  final IconData icon;
  final String label;
  final String value;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelStyle = context.textTheme.bodySm.copyWith(
      color: colors.textSecondary,
    );
    final valueStyle = context.textTheme.bodySmMedium.copyWith(
      color: colors.textPrimary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: colors.iconPrimary),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
            child: Text(
              label,
              style: labelStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: valueStyle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
