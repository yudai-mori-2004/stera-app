import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_sizes.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_state.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart" show Colors;

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.borderColor,
    this.borderRadius,
    this.padding,
    this.width,
    this.height,
    this.leadingIcon,
    this.trailingIcon,
    this.textStyle,
    this.type = ButtonType.primary,
    this.size = ButtonSizes.lg,
    this.showShadow = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;

  /// Optional override for the resolved background color from [ButtonType].
  final Color? backgroundColor;

  /// Optional override for the resolved text/icon color from [ButtonType].
  final Color? foregroundColor;

  /// Optional override for the disabled background color.
  final Color? disabledBackgroundColor;

  /// Optional override for the resolved border color from [ButtonType].
  final Color? borderColor;

  final double? borderRadius;

  /// Optional override for padding; otherwise driven by [size].
  final EdgeInsets? padding;
  final double? width;
  final double? height;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final TextStyle? textStyle;
  final ButtonType type;

  /// Controls base sizing (padding + text style).
  final ButtonSizes size;

  /// If true, shows elevation-like shadow when enabled and supported by type.
  final bool showShadow;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final bool isDisabledEffective =
        widget.isDisabled || widget.onPressed == null || widget.isLoading;

    final ButtonState state = isDisabledEffective
        ? ButtonState.disabled
        : ButtonState.defaultState;

    // Resolve colors from design tokens, allowing explicit overrides.
    final Color? resolvedBg =
        widget.backgroundColor ?? widget.type.backgroundColor(context, state);
    final Color fgColor =
        widget.foregroundColor ?? widget.type.textColor(context, state);
    final Color? disabledBg =
        widget.disabledBackgroundColor ??
        widget.type.backgroundColor(context, ButtonState.disabled);
    final Color? resolvedBorderColor =
        widget.borderColor ?? widget.type.borderColor(context, state);

    final double borderRadius = widget.borderRadius ?? 12.0;
    final EdgeInsets resolvedPadding =
        widget.padding ?? widget.size.padding(context);
    final TextStyle resolvedTextStyle =
        (widget.textStyle ?? widget.size.text(context)).copyWith(
          color: fgColor,
        );

    return Pressable(
      onTap: widget.onPressed,
      enabled: !isDisabledEffective,
      child: Container(
        width: widget.width ?? double.infinity,
        height: widget.height,
        padding: resolvedPadding,
        decoration: ShapeDecoration(
          color: isDisabledEffective ? disabledBg : resolvedBg,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(
              color: resolvedBorderColor ?? Colors.transparent,
              width: resolvedBorderColor == null ? 0 : 1,
            ),
          ),
          shadows:
              widget.showShadow &&
                  !isDisabledEffective &&
                  widget.type == ButtonType.primary
              ? [
                  BoxShadow(
                    color: context.isDarkMode
                        ? colors.neutralWhite.withValues(alpha: 0.12)
                        : colors.neutralBlack.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(child: _buildContent(fgColor, resolvedTextStyle)),
      ),
    );
  }

  Widget _buildContent(Color fgColor, TextStyle resolvedTextStyle) {
    // For primary & secondary: show only spinner when loading.
    if (widget.isLoading && widget.type != ButtonType.tertiary) {
      return CupertinoActivityIndicator(color: fgColor);
    }

    // For tertiary: keep the label visible and show a trailing spinner.
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leadingIcon != null) ...[
          widget.leadingIcon!,
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(widget.text, style: resolvedTextStyle),
        if (widget.type == ButtonType.tertiary && widget.isLoading) ...[
          const SizedBox(width: AppSpacing.sm),
          CupertinoActivityIndicator(color: fgColor),
        ] else if (widget.trailingIcon != null) ...[
          const SizedBox(width: AppSpacing.sm),
          widget.trailingIcon!,
        ],
      ],
    );
  }
}
