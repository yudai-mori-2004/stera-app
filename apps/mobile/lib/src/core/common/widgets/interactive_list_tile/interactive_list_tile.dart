import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_toggle_switch.dart";
import "package:stera/src/core/common/widgets/selectable_chip.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/enums/interactive_list_tile_enums.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/extensions/interactive_list_tile_background_color.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/extensions/interactive_list_tile_text_style.dart";
import "package:stera/src/core/common/widgets/interactive_list_tile/extensions/leading.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

/// A single interactive row: title + optional subtitle, a leading icon, and a
/// trailing affordance chosen by [action] (toggle, chevron, arrow, expander).
/// Supports an inline [extention] / animated [animatedExtension] that reveals
/// extra content below the row.
///
/// Styled in this app's design language — titles use [headMd], subtitles
/// [bodySm], toggles reuse [AppToggleSwitch]. Usually composed via
/// [InteractiveList], which wires corner rounding and dividers.
class InteractiveListTile extends StatefulWidget {
  final String title;
  final String? subTitle;
  final InteractiveListTileType type;
  final InteractiveListTileAction action;
  final InteractiveListTileIconState iconState;
  final bool? isDisabled;
  final bool isLoading;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final bool? switchValue;
  final Function(bool)? onToggle;
  final String? bottomSheetTrailingText;
  final IconData? icon;
  final String? iconPath;
  final bool? showBorder;
  final bool isTitleSmall;
  final Widget? extention;
  final bool isFullWidth;
  final double? borderRadius;
  final ShapeBorder? customBorder;
  final Color? backgroundColor;
  final bool showTertiaryText;
  final Widget? trailing;
  final Widget? leading;
  final double? leadingIconSize;
  final EdgeInsetsGeometry? extensionPadding;
  final TextStyle? titleTextStyle;
  final TextStyle? subTitleTextStyle;
  final int? maxLines;
  final int? subTitleMaxLines;
  final bool isHighlighting;
  final VoidCallback? onExtensionTap;
  final Widget? animatedExtension;
  final ValueChanged<bool>? onExtendedChanged;
  final ValueChanged<bool>? onToggleChanged;
  final Widget? animatedExtensionTrailingWidgets;
  final bool? isExtended;
  final Widget? bottomWidget;

  /// Raw card mode: when set, the tile renders [content] inside its bordered,
  /// rounded shape and nothing else — no title row, trailing affordance, or
  /// chips. This is the design-system replacement for the old SettingsCard:
  /// use a standalone tile to wrap arbitrary grouped content (a Column of
  /// rows, a PageView, etc.). [contentPadding] defaults to a small vertical
  /// inset; pass [EdgeInsets.zero] when [content] manages its own spacing.
  final Widget? content;
  final EdgeInsetsGeometry? contentPadding;

  /// Labels for an inline [SelectableChip] selector revealed below the row —
  /// the same "toggle + option chips" modality as the old settings StreamTile.
  /// For a [InteractiveListTileAction.toggle] tile the chips appear only while
  /// toggled on; for other actions they are always shown when non-empty.
  final List<String>? chipOptions;
  final int? selectedChipIndex;
  final ValueChanged<int>? onChipSelected;

  /// Typed integer variant of [chipOptions]: supply the raw values (e.g. frame
  /// rates) and they render as `<value> Hz` chips, with selection reported back
  /// as the value via [onHzChanged]. Use this instead of hand-mapping ints to
  /// labels and indices. Ignored when [chipOptions] is set.
  final List<int>? hzOptions;
  final int? hzValue;
  final ValueChanged<int>? onHzChanged;

  const InteractiveListTile({
    super.key,
    this.title = "",
    this.subTitle,
    this.subTitleMaxLines,
    this.type = InteractiveListTileType.normal,
    this.action = InteractiveListTileAction.arrow,
    this.iconState = InteractiveListTileIconState.none,
    this.isDisabled,
    this.isLoading = false,
    this.onPressed,
    this.padding,
    this.switchValue,
    this.onToggle,
    this.bottomSheetTrailingText,
    this.icon,
    this.iconPath,
    this.showBorder = true,
    this.isTitleSmall = false,
    this.extention,
    this.isFullWidth = false,
    this.borderRadius,
    this.customBorder,
    this.backgroundColor,
    this.showTertiaryText = false,
    this.trailing,
    this.leading,
    this.leadingIconSize,
    this.extensionPadding,
    this.titleTextStyle,
    this.subTitleTextStyle,
    this.maxLines,
    this.isHighlighting = false,
    this.onExtensionTap,
    this.animatedExtension,
    this.onExtendedChanged,
    this.onToggleChanged,
    this.animatedExtensionTrailingWidgets,
    this.isExtended,
    this.bottomWidget,
    this.chipOptions,
    this.selectedChipIndex,
    this.onChipSelected,
    this.hzOptions,
    this.hzValue,
    this.onHzChanged,
    this.content,
    this.contentPadding,
  });

  @override
  State<InteractiveListTile> createState() => _InteractiveListTileState();
}

class _InteractiveListTileState extends State<InteractiveListTile>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<InteractiveListTileState> _tileState;
  late final AnimationController _highlightController;
  late final Animation<double> _highlightAnimation;
  final ValueNotifier<bool> _isExtended = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isToggled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _tileState = ValueNotifier<InteractiveListTileState>(
      (widget.isDisabled ?? false)
          ? InteractiveListTileState.disabled
          : InteractiveListTileState.normal,
    );
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _highlightAnimation = CurvedAnimation(
      parent: _highlightController,
      curve: Curves.fastEaseInToSlowEaseOut,
    );
    if (widget.isHighlighting) {
      _triggerHighlight();
    }

    _isExtended.value = widget.isExtended ?? false;
    _isToggled.value = widget.switchValue ?? false;
  }

  void _toggleChanged() async {
    _isToggled.value = !_isToggled.value;
    _tileState.value = InteractiveListTileState.disabled;
    await widget.onToggle?.call(_isToggled.value);
    if (widget.animatedExtension != null) {
      _toggleIsExtended();
    }
    _tileState.value = InteractiveListTileState.normal;
    widget.onToggleChanged?.call(_isToggled.value);
  }

  void _toggleIsExtended() {
    _isExtended.value = !_isExtended.value;
    widget.onExtendedChanged?.call(_isExtended.value);
  }

  void _triggerHighlight() {
    _highlightController.forward(from: 0.0);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _highlightController.reverse();
    });
  }

  @override
  void didUpdateWidget(InteractiveListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDisabled != widget.isDisabled) {
      _tileState.value = (widget.isDisabled ?? false)
          ? InteractiveListTileState.disabled
          : InteractiveListTileState.normal;
    }
    if (!oldWidget.isHighlighting && widget.isHighlighting) {
      _triggerHighlight();
    }
    if (oldWidget.isExtended != widget.isExtended &&
        widget.isExtended != null) {
      _isExtended.value = widget.isExtended!;
    }
    if (oldWidget.switchValue != widget.switchValue &&
        widget.switchValue != null) {
      _isToggled.value = widget.switchValue!;
      widget.onToggleChanged?.call(_isToggled.value);
    }
  }

  @override
  void dispose() {
    _tileState.dispose();
    _isExtended.dispose();
    _isToggled.dispose();
    _highlightController.dispose();
    super.dispose();
  }

  /// Reveals [child] below the row with a synchronized slide + fade + size
  /// animation, anchored top-left. Collapses to zero height (clipped) when
  /// [revealed] is false so it takes no layout while hidden.
  Widget _animatedReveal({
    required bool revealed,
    required Widget child,
    EdgeInsetsGeometry? padding,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding:
          padding ??
          EdgeInsets.symmetric(vertical: revealed ? AppSpacing.md : AppSpacing.none, horizontal: AppSpacing.lg),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRect(
          child: AnimatedSlide(
            offset: revealed ? Offset.zero : const Offset(0, -0.1),
            duration: const Duration(milliseconds: 450),
            curve: revealed
                ? Curves.fastEaseInToSlowEaseOut
                : Curves.fastLinearToSlowEaseIn,
            child: AnimatedOpacity(
              opacity: revealed ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 350),
              curve: revealed
                  ? Curves.fastEaseInToSlowEaseOut
                  : Curves.fastLinearToSlowEaseIn,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 400),
                curve: Curves.fastEaseInToSlowEaseOut,
                alignment: Alignment.topLeft,
                child: revealed
                    ? Align(alignment: Alignment.topLeft, child: child)
                    : SizedBox(
                        width: double.infinity,
                        height: 0,
                        child: OverflowBox(maxHeight: 0, child: child),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showBorder = (widget.showBorder ?? false);
    final border =
        widget.customBorder ??
        (widget.isFullWidth
            ? const RoundedRectangleBorder()
            : RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius ?? 14),
                side: showBorder
                    ? BorderSide(color: context.colors.borderDivider, width: 1)
                    : BorderSide.none,
              ));

    // Raw card mode: just the bordered, clipped container around [content].
    if (widget.content != null) {
      final pad =
          widget.contentPadding ?? const EdgeInsets.symmetric(vertical: AppSpacing.xs);
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: widget.backgroundColor ?? context.colors.surfacePrimary,
          shape: border,
        ),
        child: pad == EdgeInsets.zero
            ? widget.content!
            : Padding(padding: pad, child: widget.content!),
      );
    }

    // Effective chip selector, derived from the string API or the typed-int
    // ([hzOptions]) convenience — the latter labels values as "<n> Hz" and
    // reports selection back as the value.
    final List<String>? chipLabels =
        widget.chipOptions ?? widget.hzOptions?.map((hz) => "$hz Hz").toList();
    final int? selectedChip =
        widget.chipOptions != null || widget.hzOptions == null
        ? widget.selectedChipIndex
        : (widget.hzValue == null
              ? null
              : widget.hzOptions!.indexOf(widget.hzValue!));
    void onChipSelected(int i) {
      widget.onChipSelected?.call(i);
      if (widget.chipOptions == null && widget.hzOptions != null) {
        widget.onHzChanged?.call(widget.hzOptions![i]);
      }
    }

    return ValueListenableBuilder(
      valueListenable: _tileState,
      builder: (context, state, child) {
        return ValueListenableBuilder(
          valueListenable: _isExtended,
          builder: (context, isExtended, child) {
            return ValueListenableBuilder(
              valueListenable: _isToggled,
              builder: (context, toggle, child) {
                return InkWell(
                  onTap: widget.action == InteractiveListTileAction.extended
                      ? _toggleIsExtended
                      : widget.action == InteractiveListTileAction.toggle
                      ? _toggleChanged
                      : widget.onPressed,
                  onHover: (hovering) {
                    if (widget.isDisabled == true) return;
                    hovering
                        ? _tileState.value = InteractiveListTileState.hover
                        : _tileState.value = InteractiveListTileState.normal;
                  },
                  customBorder: border,
                  child: AnimatedBuilder(
                    animation: _highlightController,
                    builder: (context, child) {
                      final baseColor =
                          widget.backgroundColor ??
                          widget.type.backgroundColor(context, state);
                      final highlightColor = context.colors.blue.withValues(
                        alpha: context.isDarkMode ? 0.30 : 0.12,
                      );
                      final Color? color = Color.lerp(
                        baseColor,
                        highlightColor,
                        _highlightAnimation.value,
                      );
                      // Chips follow the toggle for a toggle tile, the expander
                      // for an extended tile, and are always shown otherwise.
                      final bool chipsRevealed =
                          widget.action == InteractiveListTileAction.toggle
                          ? toggle
                          : widget.action == InteractiveListTileAction.extended
                          ? isExtended
                          : true;
                      return Container(
                        decoration: ShapeDecoration(
                          color: color,
                          shape: border,
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding:
                                  widget.padding ??
                                  const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                    horizontal: AppSpacing.lg,
                                  ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  if (widget.iconState !=
                                          InteractiveListTileIconState.none &&
                                      widget.type !=
                                          InteractiveListTileType.bulletedInfo)
                                    Padding(
                                      padding: const EdgeInsets.only(right: AppSpacing.lg),
                                      child:
                                          widget.leading ??
                                          widget.iconState.buildLeading(
                                            icon: widget.icon,
                                            iconPath: widget.iconPath,
                                            iconSize: widget.leadingIconSize,
                                          ),
                                    ),
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (widget.type ==
                                            InteractiveListTileType
                                                .bulletedInfo)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: AppSpacing.sm,
                                            ),
                                            child: Text(
                                              "•",
                                              style: widget.type.titleTextStyle(
                                                context,
                                                widget.isTitleSmall,
                                              ),
                                            ),
                                          ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.title,
                                                style:
                                                    widget.titleTextStyle ??
                                                    widget.type
                                                        .titleTextStyle(
                                                          context,
                                                          widget.isTitleSmall,
                                                        )
                                                        .copyWith(
                                                          color:
                                                              widget
                                                                  .showTertiaryText
                                                              ? context
                                                                    .colors
                                                                    .textTertiary
                                                              : null,
                                                        ),
                                                maxLines: widget.maxLines,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (widget.subTitle != null) ...[
                                                const SizedBox(height: AppSpacing.xs),
                                                Text(
                                                  widget.subTitle!,
                                                  maxLines:
                                                      widget.subTitleMaxLines,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      widget
                                                          .subTitleTextStyle ??
                                                      widget.type
                                                          .subTitleTextStyle(
                                                            context,
                                                            widget.isTitleSmall,
                                                          )
                                                          .copyWith(
                                                            color:
                                                                widget
                                                                    .showTertiaryText
                                                                ? context
                                                                      .colors
                                                                      .textTertiary
                                                                : null,
                                                          ),
                                                ),
                                              ],
                                              if (widget.bottomWidget != null)
                                                widget.bottomWidget!,
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  widget.trailing ??
                                      switch (widget.action) {
                                        InteractiveListTileAction.toggle =>
                                          AppToggleSwitch(
                                            value: toggle,
                                            onChanged: widget.isDisabled == true
                                                ? null
                                                : (_) => _toggleChanged(),
                                          ),
                                        InteractiveListTileAction.bottomSheet =>
                                          Row(
                                            children: [
                                              if (widget
                                                      .bottomSheetTrailingText !=
                                                  null) ...[
                                                Text(
                                                  widget
                                                      .bottomSheetTrailingText!,
                                                  style: context
                                                      .textTheme
                                                      .bodySm
                                                      .copyWith(
                                                        color: context
                                                            .colors
                                                            .textSecondary,
                                                      ),
                                                ),
                                                const SizedBox(width: AppSpacing.xs),
                                              ],
                                              AnimatedRotation(
                                                turns:
                                                    widget.switchValue != null
                                                    ? (widget.switchValue!
                                                          ? 1
                                                          : 0.0)
                                                    : 0.0,
                                                duration: const Duration(
                                                  milliseconds: 900,
                                                ),
                                                curve: Curves
                                                    .fastEaseInToSlowEaseOut,
                                                child: Icon(
                                                  widget.switchValue != null
                                                      ? (widget.switchValue!
                                                            ? Icons.expand_less
                                                            : Icons.expand_more)
                                                      : Icons.expand_more,
                                                  color: context
                                                      .colors
                                                      .textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        InteractiveListTileAction.arrow => Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                          color: context.colors.textTertiary,
                                        ),
                                        InteractiveListTileAction.extended => Row(
                                          children: [
                                            if (widget
                                                    .animatedExtensionTrailingWidgets !=
                                                null) ...[
                                              widget
                                                  .animatedExtensionTrailingWidgets!,
                                              const SizedBox(width: AppSpacing.xs),
                                            ],
                                            AnimatedRotation(
                                              turns: isExtended ? 0.5 : 0.0,
                                              duration: const Duration(
                                                milliseconds: 900,
                                              ),
                                              curve: Curves
                                                  .fastEaseInToSlowEaseOut,
                                              child: Icon(
                                                Icons.expand_more,
                                                color: context
                                                    .colors
                                                    .textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        InteractiveListTileAction.none =>
                                          const SizedBox.shrink(),
                                      },
                                ],
                              ),
                            ),
                            if (chipLabels != null && chipLabels.isNotEmpty)
                              _animatedReveal(
                                revealed: chipsRevealed,
                                padding: EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  AppSpacing.none,
                                  AppSpacing.lg,
                                  chipsRevealed ? AppSpacing.md : AppSpacing.none,
                                ),
                                child: Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: 8,
                                  children: [
                                    for (var i = 0; i < chipLabels.length; i++)
                                      _StaggeredChip(
                                        visible: chipsRevealed,
                                        delay: Duration(
                                          milliseconds: chipsRevealed
                                              ? i * 45
                                              : 0,
                                        ),
                                        child: SelectableChip(
                                          label: chipLabels[i],
                                          selected: selectedChip == i,
                                          onSelected: () => onChipSelected(i),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            if (widget.animatedExtension != null)
                              _animatedReveal(
                                revealed: isExtended,
                                padding: widget.extensionPadding,
                                onTap: widget.onExtensionTap,
                                child: widget.animatedExtension!,
                              )
                            else if (widget.extention != null)
                              Padding(
                                padding:
                                    widget.extensionPadding ??
                                    const EdgeInsets.symmetric(
                                      vertical: AppSpacing.md,
                                      horizontal: AppSpacing.lg,
                                    ),
                                child: widget.extention!,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Fades + scales its [child] in once [visible] becomes true, after [delay].
/// Re-plays every time the selector is revealed (toggled back on), so a row of
/// these with increasing delays produces a staggered entrance. Selecting a chip
/// does not re-trigger it — only a [visible] false→true transition does.
class _StaggeredChip extends StatefulWidget {
  const _StaggeredChip({
    required this.visible,
    required this.delay,
    required this.child,
  });

  final bool visible;
  final Duration delay;
  final Widget child;

  @override
  State<_StaggeredChip> createState() => _StaggeredChipState();
}

class _StaggeredChipState extends State<_StaggeredChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: widget.visible ? 1.0 : 0.0,
    );
    if (widget.visible) _play();
  }

  void _play() {
    _controller.value = 0.0;
    Future.delayed(widget.delay, () {
      if (mounted && widget.visible) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(_StaggeredChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _play();
    } else if (!widget.visible && oldWidget.visible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: Curves.easeOut)),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
        ),
        alignment: Alignment.centerLeft,
        child: widget.child,
      ),
    );
  }
}
