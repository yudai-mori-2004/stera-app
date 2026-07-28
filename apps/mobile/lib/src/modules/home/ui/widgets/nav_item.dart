import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";

class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.iconPath,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String iconPath;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      behavior: HitTestBehavior.opaque,
      pressedScale: 0.9,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            iconPath,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              isActive
                  ? context.colors.textPrimary
                  : context.colors.textTertiary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: context.textTheme.bodyXsMono.copyWith(
              fontWeight: isActive ? AppType.semibold : AppType.medium,
            ),
          ),
        ],
      ),
    );
  }
}
