import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

/// Small amber pill marking this as the open-source build. Used in the home
/// header and in the profile footer.
///
/// The rest of the UI is deliberately near-monochrome (everything keys off
/// `textPrimary`), so this pill and its [C.brandAccent] tint are the only
/// chromatic cue that distinguishes RootLens from the closed-source app.
class OpenSourceBadge extends StatelessWidget {
  const OpenSourceBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.brandAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: ShapeDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.full),
          side: BorderSide(color: accent.withValues(alpha: 0.55)),
        ),
      ),
      child: Text(
        "OPEN SOURCE",
        style: context.textTheme.bodyXsMedium.copyWith(
          color: accent,
          letterSpacing: 0.6,
          fontWeight: AppType.bold,
        ),
      ),
    );
  }
}
