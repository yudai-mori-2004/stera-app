import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

/// A single action in an [AppPopupMenu].
class AppPopupMenuItem {
  const AppPopupMenuItem({
    required this.label,
    required this.onSelected,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback onSelected;
  final bool isDestructive;
}

/// Design-system popup menu: [surfaceSecondary] surface, superellipse shape,
/// border + shadow matching [AppToast], Geist typography, light haptic on select.
class AppPopupMenu extends StatelessWidget {
  const AppPopupMenu({
    super.key,
    required this.child,
    required this.items,
    this.offset = const Offset(0, 2),
    this.minWidth = 168,
  });

  final Widget child;
  final List<AppPopupMenuItem> items;
  final Offset offset;
  final double minWidth;

  Future<void> _showMenu(BuildContext context) async {
    if (items.isEmpty) return;

    final renderBox = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final size = renderBox.size;

    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + size.height + offset.dy,
      overlay.size.width - topLeft.dx - size.width,
      overlay.size.height - topLeft.dy - size.height - offset.dy,
    );

    final colors = context.colors;
    final isDark = context.isDarkMode;

    final selectedIndex = await showMenu<int>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: minWidth),
      color: colors.surfaceSecondary,
      elevation: 8,
      shadowColor: context.colors.neutralBlack.withValues(alpha: isDark ? 0.35 : 0.12),
      surfaceTintColor: Colors.transparent,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: colors.borderDefault),
      ),
      items: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            PopupMenuDivider(
              height: 1,
              thickness: 1,
              color: colors.borderDivider,
            ),
          PopupMenuItem<int>(
            value: i,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              items[i].label,
              style: context.textTheme.bodySmMedium.copyWith(
                color: items[i].isDestructive
                    ? colors.textDestructive
                    : colors.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );

    if (selectedIndex == null || selectedIndex >= items.length) return;

    HapticFeedback.lightImpact();
    items[selectedIndex].onSelected();
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (menuContext) {
        return Material(
          color: Colors.transparent,
          child: Pressable(
            pressedScale: 0.9,
            onTap: () => _showMenu(menuContext),
            child: child,
          ),
        );
      },
    );
  }
}
