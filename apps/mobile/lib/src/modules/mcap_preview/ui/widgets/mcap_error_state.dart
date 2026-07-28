import "package:flutter/material.dart";
import "package:solar_icons/solar_icons.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";

/// Centered error message for the MCAP preview and player pages.
/// [showIcon] is off in the fullscreen player, where the close button is
/// the only chrome and a warning glyph would compete with it.
class McapErrorState extends StatelessWidget {
  final String message;
  final bool showIcon;

  const McapErrorState({
    super.key,
    required this.message,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[
              Icon(
                SolarIconsOutline.dangerCircle,
                size: 32,
                color: context.colors.textSecondary,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySm.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
