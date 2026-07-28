import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int? number;
  final bool isError;
  final int? maxSubtitleLines;

  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.number,
    this.isError = false,
    this.maxSubtitleLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: AppSpacing.xs,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: AppSpacing.xsPlus,
          children: [
            Text(
              title,
              style: context.textTheme.headSm.copyWith(
                color: isError
                    ? context.colors.textDestructive
                    : context.colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (number != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                  ),
                  color: isError
                      ? context.colors.textDestructive
                      : context.colors.neutralBlack,
                ),
                child: Text(
                  "$number",
                  style: context.textTheme.headSm.copyWith(
                    color: context.colors.neutralWhite,
                  ),
                ),
              ),
          ],
        ),
        Text(
          subtitle,
          style: context.textTheme.bodySm,
          maxLines: maxSubtitleLines,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
