import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_text_field/enums/text_field_state.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.prefixText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
    this.validator,
    this.suffixIcon,
    this.prefixIcon,
    this.maxLines = 1,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    this.isExpanded = false,
    this.header,
    this.description,
    this.errorText,
    this.suffix,
    this.prefix,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? prefixText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool isExpanded;
  final String? header;
  final String? description;
  final String? errorText;
  final Widget? suffix;
  final Widget? prefix;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    widget.controller?.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onTextChanged);
      widget.controller?.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    widget.controller?.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  void _onFocusChanged() {
    setState(() {});
  }

  TextFieldState _effectiveState() {
    if (!widget.enabled) return TextFieldState.disabled;
    if ((widget.errorText ?? "").isNotEmpty) return TextFieldState.error;
    if (_focusNode.hasFocus) return TextFieldState.focused;
    return TextFieldState.defaultState;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = context.textTheme;
    final state = _effectiveState();
    final borderColor = state.borderColor(context);

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.md),
      borderSide: BorderSide(color: borderColor, width: 1),
    );

    final hasText = widget.controller?.text.trim().isNotEmpty ?? false;

    final header = widget.header;
    final description = widget.description;
    final hasError = (widget.errorText ?? "").isNotEmpty;

    final headerColor = state.labelColor(context);
    final descriptionColor = hasError
        ? TextFieldState.error.descriptionColor(context)
        : state.descriptionColor(context);

    final field = TextFormField(
      focusNode: _focusNode,
      cursorColor: colors.textPrimary,
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      validator: widget.validator,
      maxLines: widget.isExpanded ? 5 : widget.maxLines,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      decoration: InputDecoration(
        prefixText: widget.prefixText,
        prefixStyle: textTheme.bodySmMedium.copyWith(color: colors.textPrimary),
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.suffixIcon,
        hintText: widget.hintText,
        suffix: widget.suffix,
        prefix: hasText ? widget.prefix : null,
        hintStyle: textTheme.bodySm.copyWith(color: colors.textTertiary),
        filled: true,
        fillColor: state.backgroundColor(context),
        border: border,
        enabledBorder: border,
        disabledBorder: border.copyWith(
          borderSide: border.borderSide.copyWith(
            color: TextFieldState.disabled.borderColor(context),
          ),
        ),
        focusedBorder: border.copyWith(
          borderSide: border.borderSide.copyWith(
            color: TextFieldState.focused.borderColor(context),
          ),
        ),
        errorBorder: border.copyWith(
          borderSide: border.borderSide.copyWith(
            color: TextFieldState.error.borderColor(context),
          ),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: border.borderSide.copyWith(
            color: TextFieldState.error.borderColor(context),
          ),
        ),
        errorText: widget.errorText,
        errorStyle: textTheme.bodyXs.copyWith(color: colors.textDestructive),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.mdPlus,
        ),
      ),
      style: textTheme.bodySm.copyWith(color: state.textColor(context)),
      inputFormatters: widget.inputFormatters,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null) ...[
          Text(
            header,
            style: textTheme.bodySmMedium.copyWith(color: headerColor),
          ),
          const SizedBox(height: AppSpacing.xsPlus),
        ],
        field,
        const SizedBox(height: AppSpacing.xs),
        if (!hasError && (description ?? "").isNotEmpty) ...[
          Text(
            description!,
            style: textTheme.bodyXs.copyWith(color: descriptionColor),
          ),
        ],
      ],
    );
  }
}
