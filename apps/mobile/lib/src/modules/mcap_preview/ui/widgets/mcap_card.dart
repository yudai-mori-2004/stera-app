import "package:flutter/material.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";

/// Full-width superellipse surface card shared by the MCAP preview,
/// topic player and processing pages.
class McapCard extends StatelessWidget {
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  const McapCard({super.key, this.margin, this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.w,
      margin: margin,
      padding: padding,
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        color: context.colors.surfaceSecondary,
        shadows: [
          BoxShadow(
            color: context.colors.neutralBlack.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
