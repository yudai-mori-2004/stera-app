import "package:stera/src/core/theme/brand_palette.dart";
import "package:flutter/material.dart";

class C {
  // Text Colors
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInversePrimary;
  final Color textInverseSecondary;
  final Color textDisabled;
  final Color textAlert;
  final Color textDestructive;

  // Surface Colors
  final Color surfacePrimary;
  final Color surfaceSecondary;
  final Color surfaceTertiary;
  final Color surfaceBlack;
  final Color surfaceWhite;

  // Border Colors
  final Color borderDefault;
  final Color borderDisabled;
  final Color borderDivider;
  final Color borderError;
  final Color borderSelected;

  // Icon Colors
  final Color iconPrimary;
  final Color iconDisabled;

  // Neutral Colors
  final Color neutralDarkGray;
  final Color neutralGray;
  final Color neutralLightGray;
  final Color neutralBlack;
  final Color neutralWhite;

  // Temporary Colors
  final Color blue;
  final Color red;
  final Color green;
  final Color yellow;

  /// Fork accent. The palette is otherwise near-monochrome (everything keys
  /// off [textPrimary]); this is the single chromatic token used to mark
  /// RootLens as the open-source build. Warm amber, in the same family as
  /// the gold brand gradient below.
  final Color brandAccent;

  // Gradient Colors (brand assets; shared by light & dark [C] instances)
  final LinearGradient silverGradient = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF89A4B9), Color(0xFF324158)],
    stops: [0.0, 2.7429],
  );
  final LinearGradient goldGradient = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment(0, 4.48),
    colors: [Color(0xFFFDCD24), Color(0xFFCF6D0A)],
    stops: [0.0, 0.6786],
  );
  final LinearGradient bronzeGradient = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment(0, 4.48),
    colors: [Color(0xFFCD7B45), Color(0xFF5E3310)],
    stops: [0.0, 2.1133],
  );
  final LinearGradient greenBlueGradient = const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF162E20), Color(0xFF354667)],
    stops: [0.0, 1.0],
  );

  C({
    // Text
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInversePrimary,
    required this.textInverseSecondary,
    required this.textDisabled,
    required this.textAlert,
    required this.textDestructive,
    // Surface
    required this.surfacePrimary,
    required this.surfaceSecondary,
    required this.surfaceTertiary,
    required this.surfaceBlack,
    required this.surfaceWhite,
    // Border
    required this.borderDefault,
    required this.borderDisabled,
    required this.borderDivider,
    required this.borderError,
    required this.borderSelected,
    // Icon
    required this.iconPrimary,
    required this.iconDisabled,
    // Neutral
    required this.neutralDarkGray,
    required this.neutralGray,
    required this.neutralLightGray,
    required this.neutralBlack,
    required this.neutralWhite,

    // Temporary Colors
    required this.blue,
    required this.red,
    required this.green,
    required this.yellow,
    required this.brandAccent,
  });

  factory C.light() {
    return C(
      // Text Colors (darkest → disabled / semantic)
      textPrimary: BrandPalette.textPrimaryLight,
      textSecondary: BrandPalette.textSecondaryLight,
      textTertiary: BrandPalette.textTertiaryLight,
      textInversePrimary: BrandPalette.textInversePrimaryLight,
      textInverseSecondary: BrandPalette.textInverseSecondaryLight,
      textDisabled: BrandPalette.textDisabledLight,
      textAlert: BrandPalette.textAlertLight,
      textDestructive: BrandPalette.textDestructiveLight,

      // Surface Colors (page → card → accent)
      surfacePrimary: BrandPalette.surfacePrimaryLight,
      surfaceSecondary: BrandPalette.surfaceSecondaryLight,
      surfaceTertiary: BrandPalette.surfaceTertiaryLight,
      surfaceBlack: BrandPalette.surfaceBlackLight,
      surfaceWhite: BrandPalette.surfaceWhiteLight,

      // Border Colors
      borderDefault: BrandPalette.borderDefaultLight,
      borderDisabled: BrandPalette.borderDisabledLight,
      borderDivider: BrandPalette.borderDividerLight,
      borderError: BrandPalette.borderErrorLight,
      borderSelected: BrandPalette.borderSelectedLight,

      // Icon Colors
      iconPrimary: BrandPalette.iconPrimaryLight,
      iconDisabled: BrandPalette.iconDisabledLight,

      // Neutral Colors (dark → light gray; black/white anchors)
      neutralDarkGray: BrandPalette.neutralDarkGrayLight,
      neutralGray: BrandPalette.neutralGrayLight,
      neutralLightGray: BrandPalette.neutralLightGrayLight,
      neutralBlack: BrandPalette.neutralBlackLight,
      neutralWhite: BrandPalette.neutralWhiteLight,

      // Temporary Colors (semantic accents; tuned separately in dark)
      blue: BrandPalette.blueLight,
      red: BrandPalette.redLight,
      green: BrandPalette.greenLight,
      yellow: BrandPalette.yellowLight,
      brandAccent: BrandPalette.brandAccentLight,
    );
  }

  factory C.dark() {
    return C(
      // Text Colors (inverted for dark backgrounds)
      textPrimary: BrandPalette.textPrimaryDark,
      textSecondary: BrandPalette.textSecondaryDark,
      textTertiary: BrandPalette.textTertiaryDark,
      textInversePrimary: BrandPalette.textInversePrimaryDark,
      textInverseSecondary: BrandPalette.textInverseSecondaryDark,
      textDisabled: BrandPalette.textDisabledDark,
      textAlert: BrandPalette.textAlertDark,
      textDestructive: BrandPalette.textDestructiveDark,

      // Surface Colors (darkest → elevated)
      surfacePrimary: BrandPalette.surfacePrimaryDark,
      surfaceSecondary: BrandPalette.surfaceSecondaryDark,
      surfaceTertiary: BrandPalette.surfaceTertiaryDark,
      surfaceBlack: BrandPalette.surfaceBlackDark,
      surfaceWhite: BrandPalette.surfaceWhiteDark,

      // Border Colors (visible on dark surfaces)
      borderDefault: BrandPalette.borderDefaultDark,
      borderDisabled: BrandPalette.borderDisabledDark,
      borderDivider: BrandPalette.borderDividerDark,
      borderError: BrandPalette.borderErrorDark,
      borderSelected: BrandPalette.borderSelectedDark,

      // Icon Colors (lighter for dark mode)
      iconPrimary: BrandPalette.iconPrimaryDark,
      iconDisabled: BrandPalette.iconDisabledDark,

      // Neutral Colors (ladder for dark UI: fills → strokes/icons → muted)
      // neutralLightGray: low-elevation fills; neutralDarkGray: controls/icons on dark;
      // neutralGray: aligns with secondary label tone; neutralBlack: true black (≠ surfacePrimary)
      neutralDarkGray: BrandPalette.neutralDarkGrayDark,
      neutralGray: BrandPalette.neutralGrayDark,
      neutralLightGray: BrandPalette.neutralLightGrayDark,
      neutralBlack: BrandPalette.neutralBlackDark,
      neutralWhite: BrandPalette.neutralWhiteDark,

      // Temporary Colors (brighter / aligned with semantic text & borders on dark)
      blue: BrandPalette.blueDark,
      red: BrandPalette.redDark,
      green: BrandPalette.greenDark,
      yellow: BrandPalette.yellowDark,
      brandAccent: BrandPalette.brandAccentDark,
    );
  }
}
