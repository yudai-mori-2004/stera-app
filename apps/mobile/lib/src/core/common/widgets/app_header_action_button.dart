import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

/// Circular bordered icon button for [AppHeader] action slots.
///
/// Pass [child] instead of [icon] for custom content (e.g. a progress
/// spinner). With a null [onTap] the button renders as plain decoration so a
/// parent gesture owner (e.g. `AppPopupMenu`) can drive the press behavior.
class AppHeaderActionButton extends StatelessWidget {
  const AppHeaderActionButton({
    super.key,
    this.icon,
    this.child,
    this.onTap,
    this.semanticLabel,
    this.endPadding = 8,
  }) : assert(icon != null || child != null, "Provide an icon or a child");

  final IconData? icon;
  final Widget? child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Trailing gap to the next action; the last (edge) action uses 16.
  final double endPadding;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      padding: const EdgeInsets.all(AppSpacing.xsPlus),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.surfacePrimary,
        border: Border.all(color: context.colors.textPrimary),
      ),
      child: child ?? Icon(icon, size: 20, color: context.colors.textPrimary),
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.only(right: endPadding),
        child: onTap == null
            ? circle
            : Pressable(
                pressedScale: 0.9,
                onTap: onTap,
                semanticLabel: semanticLabel,
                child: circle,
              ),
      ),
    );
  }
}
