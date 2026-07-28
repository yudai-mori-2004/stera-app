import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_state.dart";
import "package:flutter/material.dart";

enum ButtonType { primary, secondary, tertiary }

extension ButtonTypeX on ButtonType {
  Color? backgroundColor(BuildContext context, ButtonState state) {
    final bool isDark = context.isDarkMode;
    switch (state) {
      case ButtonState.defaultState:
        return switch (this) {
          ButtonType.primary =>
            isDark ? context.colors.surfaceWhite : context.colors.neutralBlack,
          ButtonType.secondary => null,
          ButtonType.tertiary => null,
        };
      case ButtonState.hover:
        return switch (this) {
          ButtonType.primary =>
            isDark
                ? context.colors.neutralLightGray
                : context.colors.neutralDarkGray,
          ButtonType.secondary => context.colors.neutralLightGray,
          ButtonType.tertiary => null,
        };
      case ButtonState.disabled:
        return switch (this) {
          ButtonType.primary => context.colors.neutralLightGray,
          ButtonType.secondary => context.colors.neutralLightGray,
          ButtonType.tertiary => null,
        };
    }
  }

  Color textColor(BuildContext context, ButtonState state) {
    final bool isDark = context.isDarkMode;
    switch (state) {
      case ButtonState.defaultState:
        return switch (this) {
          ButtonType.primary =>
            isDark
                ? context.colors.textInversePrimary
                : context.colors.neutralWhite,
          ButtonType.secondary => context.colors.textPrimary,
          ButtonType.tertiary => context.colors.textPrimary,
        };
      case ButtonState.hover:
        return switch (this) {
          ButtonType.primary =>
            isDark
                ? context.colors.textInversePrimary
                : context.colors.neutralWhite,
          ButtonType.secondary => context.colors.textPrimary,
          ButtonType.tertiary => context.colors.textPrimary,
        };
      case ButtonState.disabled:
        return switch (this) {
          ButtonType.primary => context.colors.textDisabled,
          ButtonType.secondary => context.colors.textDisabled,
          ButtonType.tertiary => context.colors.textDisabled,
        };
    }
  }

  Color? borderColor(BuildContext context, ButtonState state) {
    switch (state) {
      case ButtonState.defaultState:
        return switch (this) {
          ButtonType.primary => null,
          ButtonType.secondary => context.colors.borderDefault,
          ButtonType.tertiary => null,
        };
      case ButtonState.hover:
        return switch (this) {
          ButtonType.primary => null,
          ButtonType.secondary => context.colors.borderSelected,
          ButtonType.tertiary => null,
        };
      case ButtonState.disabled:
        return switch (this) {
          ButtonType.primary => null,
          ButtonType.secondary => context.colors.borderDisabled,
          ButtonType.tertiary => null,
        };
    }
  }
}
