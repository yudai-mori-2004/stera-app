import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";

/// Marks a build running with `NO_AUTH_MODE=true`: no account, no upload, no
/// network. Shown in the settings screen so it's never a mystery why the
/// account and upload surfaces are missing.
///
/// Shaped like [OpenSourceBadge] but keyed off [C.textSecondary] rather than
/// the brand accent — this states a build configuration, and shouldn't compete
/// with the one chromatic cue the UI already spends on "open source".
class NoAuthModeBadge extends StatelessWidget {
  const NoAuthModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final tint = context.colors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: ShapeDecoration(
        color: tint.withValues(alpha: 0.10),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.full),
          side: BorderSide(color: tint.withValues(alpha: 0.45)),
        ),
      ),
      child: Text(
        "NO AUTH MODE",
        style: context.textTheme.bodyXsMedium.copyWith(
          color: tint,
          letterSpacing: 0.6,
          fontWeight: AppType.bold,
        ),
      ),
    );
  }
}
