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
  /// Stera as the open-source build. Warm amber, in the same family as
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
      textPrimary: const Color(0xFF18191B),
      textSecondary: const Color(0xFF737373),
      textTertiary: const Color(0xFFBBBEC3),
      textInversePrimary: const Color(0xFFFFFFFF),
      textInverseSecondary: const Color(0x99FFFFFF),
      textDisabled: const Color(0xFFC7C7C7),
      textAlert: const Color(0xFFB27700),
      textDestructive: const Color(0xFFD32F2F),

      // Surface Colors (page → card → accent)
      surfacePrimary: const Color(0xFFF8F9FA),
      surfaceSecondary: const Color(0xFFFFFFFF),
      surfaceTertiary: const Color(0xFFF7F4ED),
      surfaceBlack: const Color(0xFF18191B),
      surfaceWhite: const Color(0xFFFFFFFF),

      // Border Colors
      borderDefault: const Color(0xFFB7B7B7),
      borderDisabled: const Color(0xFFC7C7C7),
      borderDivider: const Color(0xFFE0E0E0),
      borderError: const Color(0xFFD32F2F),
      borderSelected: const Color(0xFF000000),

      // Icon Colors
      iconPrimary: const Color(0xFF737373),
      iconDisabled: const Color(0xFFC7C7C7),

      // Neutral Colors (dark → light gray; black/white anchors)
      neutralDarkGray: const Color(0xFF737373),
      neutralGray: const Color(0xFFBBBEC3),
      neutralLightGray: const Color(0xFFEBEBEB),
      neutralBlack: const Color(0xFF18191B),
      neutralWhite: const Color(0xFFFFFFFF),

      // Temporary Colors (semantic accents; tuned separately in dark)
      blue: const Color(0xFF007AFF),
      red: const Color(0xFFD32F2F),
      green: const Color(0xFF047A00),
      yellow: const Color(0xFFFFB740),
      brandAccent: const Color(0xFFE8A33D),
    );
  }

  factory C.dark() {
    return C(
      // Text Colors (inverted for dark backgrounds)
      textPrimary: const Color(0xFFFFFFFF),
      textSecondary: const Color(0xFFBBBEC3),
      textTertiary: const Color(0xFF737373),
      textInversePrimary: const Color(0xFF18191B),
      textInverseSecondary: const Color(0x9918191B),
      textDisabled: const Color(0xFF5C5C5C),
      textAlert: const Color(0xFFFFB740),
      textDestructive: const Color(0xFFEF5350),

      // Surface Colors (darkest → elevated)
      surfacePrimary: const Color(0xFF18191B),
      surfaceSecondary: const Color(0xFF232426),
      surfaceTertiary: const Color(0xFF2E2F31),
      surfaceBlack: const Color(0xFF000000),
      surfaceWhite: const Color(0xFFFFFFFF),

      // Border Colors (visible on dark surfaces)
      borderDefault: const Color(0xFF5C5C5C),
      borderDisabled: const Color(0xFF3D3D3D),
      borderDivider: const Color(0xFF3D3D3D),
      borderError: const Color(0xFFEF5350),
      borderSelected: const Color(0xFFFFFFFF),

      // Icon Colors (lighter for dark mode)
      iconPrimary: const Color(0xFFBBBEC3),
      iconDisabled: const Color(0xFF5C5C5C),

      // Neutral Colors (ladder for dark UI: fills → strokes/icons → muted)
      // neutralLightGray: low-elevation fills; neutralDarkGray: controls/icons on dark;
      // neutralGray: aligns with secondary label tone; neutralBlack: true black (≠ surfacePrimary)
      neutralDarkGray: const Color(0xFF8E8E93),
      neutralGray: const Color(0xFFBBBEC3),
      neutralLightGray: const Color(0xFF3D3D3D),
      neutralBlack: const Color(0xFF000000),
      neutralWhite: const Color(0xFFFFFFFF),

      // Temporary Colors (brighter / aligned with semantic text & borders on dark)
      blue: const Color(0xFF0A84FF),
      red: const Color(0xFFEF5350),
      green: const Color(0xFF32D74B),
      yellow: const Color(0xFFFFB740),
      brandAccent: const Color(0xFFFFB740),
    );
  }
}
