import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";

enum TextFieldState { defaultState, focused, disabled, error }

extension TextFieldStateX on TextFieldState {
  Color borderColor(BuildContext context) {
    final colors = context.colors;

    switch (this) {
      case TextFieldState.defaultState:
        return colors.borderDefault;
      case TextFieldState.focused:
        return colors.borderSelected;
      case TextFieldState.disabled:
        return colors.borderDisabled;
      case TextFieldState.error:
        return colors.borderError;
    }
  }

  Color backgroundColor(BuildContext context) {
    final colors = context.colors;

    switch (this) {
      case TextFieldState.defaultState:
      case TextFieldState.focused:
      case TextFieldState.error:
        return colors.surfaceSecondary;
      case TextFieldState.disabled:
        return colors.surfacePrimary;
    }
  }

  Color labelColor(BuildContext context) {
    final colors = context.colors;

    switch (this) {
      case TextFieldState.defaultState:
      case TextFieldState.focused:
        return colors.textSecondary;
      case TextFieldState.disabled:
        return colors.textDisabled;
      case TextFieldState.error:
        return colors.textDestructive;
    }
  }

  Color descriptionColor(BuildContext context) {
    final colors = context.colors;

    switch (this) {
      case TextFieldState.defaultState:
      case TextFieldState.focused:
        return colors.textTertiary;
      case TextFieldState.disabled:
        return colors.textDisabled;
      case TextFieldState.error:
        return colors.textDestructive;
    }
  }

  Color textColor(BuildContext context) {
    final colors = context.colors;

    switch (this) {
      case TextFieldState.defaultState:
      case TextFieldState.focused:
        return colors.textPrimary;
      case TextFieldState.disabled:
        return colors.textDisabled;
      case TextFieldState.error:
        return colors.textPrimary;
    }
  }
}
