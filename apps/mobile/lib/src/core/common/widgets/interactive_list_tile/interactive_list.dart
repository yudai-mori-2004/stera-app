import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/enums/interactive_list_tile_enums.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/interactive_list_tile.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

/// A bordered, rounded container that stacks [InteractiveListTile]s with
/// dividers and rounds only the outer corners — the design-system equivalent of
/// a settings card. Per-tile fields can be overridden centrally via the
/// list-level props (e.g. [titleTextStyle], [iconState], [trailing]).
class InteractiveList extends StatelessWidget {
  final List<InteractiveListTile> children;
  final EdgeInsetsGeometry padding;
  final BoxDecoration? decoration;
  final Color? backgroundColor;
  final bool isFullWidth;
  final InteractiveListTileAction? action;
  final TextStyle? titleTextStyle;
  final TextStyle? subTitleTextStyle;
  final InteractiveListTileIconState? iconState;
  final bool? showDividers;
  final Color? tileColors;
  final int? subTitleMaxLines;
  final int? titleMaxLines;
  final Widget? leading;
  final EdgeInsetsGeometry? itemPadding;
  final bool? showShadow;
  final double? leadingIconSize;
  final Widget? trailing;
  final Widget? bottomWidget;

  const InteractiveList({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
    this.decoration,
    this.backgroundColor,
    this.isFullWidth = false,
    this.action,
    this.titleTextStyle,
    this.subTitleTextStyle,
    this.iconState,
    this.showDividers,
    this.tileColors,
    this.subTitleMaxLines,
    this.titleMaxLines,
    this.leading,
    this.itemPadding,
    this.showShadow,
    this.leadingIconSize,
    this.trailing,
    this.bottomWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration:
          decoration ??
          ShapeDecoration(
            color: backgroundColor ?? context.colors.surfacePrimary,
            shape: isFullWidth
                ? const RoundedRectangleBorder()
                : RoundedSuperellipseBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdPlus)),
                    side: BorderSide(
                      color: context.colors.borderDivider,
                      width: 1,
                    ),
                  ),
            shadows: showShadow == true
                ? [
                    BoxShadow(
                      color: context.isDarkMode
                          ? context.colors.neutralWhite.withValues(alpha: 0.10)
                          : context.colors.neutralBlack.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
      child: children.isEmpty
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(children.length * 2 - 1, (index) {
                if (index.isOdd) {
                  return Visibility(
                    visible: showDividers != false,
                    replacement: const SizedBox.shrink(),
                    child: Divider(
                      color: context.colors.borderDivider,
                      thickness: 1,
                      height: 1,
                      endIndent: 16,
                      indent: 16,
                    ),
                  );
                }

                final item = children[index ~/ 2];
                final isFirst = index ~/ 2 == 0;
                final isLast = index ~/ 2 == children.length - 1;
                return InteractiveListTile(
                  key: item.key,
                  title: item.title,
                  subTitle: item.subTitle,
                  type: item.type,
                  action: action ?? item.action,
                  iconState: iconState ?? item.iconState,
                  isDisabled: item.isDisabled,
                  isLoading: item.isLoading,
                  onPressed: item.onPressed,
                  padding: itemPadding ?? item.padding,
                  switchValue: item.switchValue,
                  onToggle: item.onToggle,
                  bottomSheetTrailingText: item.bottomSheetTrailingText,
                  icon: item.icon,
                  iconPath: item.iconPath,
                  showBorder: false,
                  extention: item.extention,
                  isTitleSmall: item.isTitleSmall,
                  isFullWidth: item.isFullWidth,
                  borderRadius: item.borderRadius,
                  backgroundColor: tileColors ?? item.backgroundColor,
                  showTertiaryText: item.showTertiaryText,
                  isHighlighting: item.isHighlighting,
                  animatedExtension: item.animatedExtension,
                  animatedExtensionTrailingWidgets:
                      item.animatedExtensionTrailingWidgets,
                  isExtended: item.isExtended,
                  onExtendedChanged: item.onExtendedChanged,
                  onExtensionTap: item.onExtensionTap,
                  onToggleChanged: item.onToggleChanged,
                  customBorder: isFullWidth
                      ? const RoundedRectangleBorder()
                      : RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(
                              isFirst ? (item.borderRadius ?? 14) : 0,
                            ),
                            topRight: Radius.circular(
                              isFirst ? (item.borderRadius ?? 14) : 0,
                            ),
                            bottomLeft: Radius.circular(
                              isLast ? (item.borderRadius ?? 14) : 0,
                            ),
                            bottomRight: Radius.circular(
                              isLast ? (item.borderRadius ?? 14) : 0,
                            ),
                          ),
                          side: BorderSide.none,
                        ),
                  trailing: item.trailing ?? trailing,
                  leading: leading ?? item.leading,
                  leadingIconSize: leadingIconSize ?? item.leadingIconSize,
                  extensionPadding: item.extensionPadding,
                  subTitleTextStyle:
                      subTitleTextStyle ?? item.subTitleTextStyle,
                  titleTextStyle: titleTextStyle ?? item.titleTextStyle,
                  maxLines: titleMaxLines ?? item.maxLines,
                  subTitleMaxLines: subTitleMaxLines ?? item.subTitleMaxLines,
                  bottomWidget: item.bottomWidget ?? bottomWidget,
                  chipOptions: item.chipOptions,
                  selectedChipIndex: item.selectedChipIndex,
                  onChipSelected: item.onChipSelected,
                  hzOptions: item.hzOptions,
                  hzValue: item.hzValue,
                  onHzChanged: item.onHzChanged,
                  content: item.content,
                  contentPadding: item.contentPadding,
                );
              }),
            ),
    );
  }
}
