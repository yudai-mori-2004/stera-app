import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:motor/motor.dart";

/// A pill-shaped [ChoiceChip] styled for the app's settings selectors:
/// green when [selected], neutral surface otherwise.
class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    // Pressable owns the tap (springing the chip down and bouncing it back on
    // release); the ChoiceChip is ignored for hit-testing so it only paints the
    // selected/unselected visual. Opaque behavior is required because
    // IgnorePointer removes the child from the hit test — deferToChild would
    // never see a target and the tap would fall through to a parent InkWell.
    return Pressable(
      onTap: onSelected,
      behavior: HitTestBehavior.opaque,
      pressedScale: 0.9,
      motion: const CupertinoMotion.bouncy(),
      child: IgnorePointer(
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) {},
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smPlus, vertical: AppSpacing.xxs),
          labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          selectedColor: context.colors.green.withValues(alpha: 0.18),
          backgroundColor: context.colors.surfaceSecondary,
          side: BorderSide(
            color: selected
                ? context.colors.green
                : context.colors.borderDivider,
            width: selected ? 1.25 : 1,
          ),
          labelStyle: context.textTheme.bodySmMedium.copyWith(
            color: selected ? context.colors.green : context.colors.textPrimary,
          ),
          showCheckmark: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      ),
    );
  }
}
