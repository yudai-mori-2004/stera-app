import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_toggle_switch.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

/// A titled, subtitled row with a trailing [AppToggleSwitch] — used inside
/// settings cards to toggle a single boolean option.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textTheme.headMd.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: AppType.semibold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
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
          AppToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
