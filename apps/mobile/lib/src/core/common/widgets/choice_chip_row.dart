import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/selectable_chip.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

/// A titled, subtitled settings row with a wrapping set of single-select
/// [SelectableChip]s. Generic over the option type [T]; [labelBuilder]
/// renders each option's chip text.
class ChoiceChipRow<T> extends StatelessWidget {
  const ChoiceChipRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.value,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<T> options;
  final T value;
  final String Function(T option) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
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
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 8,
            children: options.map((option) {
              return SelectableChip(
                label: labelBuilder(option),
                selected: value == option,
                onSelected: () => onChanged(option),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
