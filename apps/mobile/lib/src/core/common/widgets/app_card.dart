import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

/// Standard content card: superellipse corners on [C.surfaceSecondary], a
/// soft shadow in light mode and a hairline border in dark mode (shadows
/// don't read on dark surfaces, so the edge carries the elevation).
///
/// Pass [onTap] to make the whole card pressable with the app's spring feel.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.radius = 16,
    this.onTap,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final card = Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: ShapeDecoration(
        color: context.colors.surfaceSecondary,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius),
          side: isDark
              ? BorderSide(color: context.colors.borderDivider)
              : BorderSide.none,
        ),
        shadows: isDark
            ? null
            : [
                BoxShadow(
                  color: context.colors.neutralBlack.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      pressedScale: pressedScale,
      onTap: onTap,
      child: card,
    );
  }
}
