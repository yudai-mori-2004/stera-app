import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/colors.dart";
// `CupertinoPageTransitionsBuilder` is not re-exported by material.dart on this
// Flutter version, so this import is load-bearing despite the analyzer hint.
// ignore: unnecessary_import
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";

class AppTheme {
  static C get lightColors => C.light();
  static C get darkColors => C.dark();

  static ThemeData get light => ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: lightColors.surfacePrimary,
    pageTransitionsTheme: pageTransitionsTheme(),
    datePickerTheme: _datePickerTheme(lightColors),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: lightColors.textPrimary,
      ),
    ),
  );

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: darkColors.surfacePrimary,
    pageTransitionsTheme: pageTransitionsTheme(),
    datePickerTheme: _datePickerTheme(darkColors),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: darkColors.textPrimary,
      ),
    ),
  );

  static DatePickerThemeData _datePickerTheme(C colors) {
    return DatePickerThemeData(
      backgroundColor: colors.surfaceSecondary,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: colors.surfaceBlack,
      headerForegroundColor: colors.textInversePrimary,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.textInversePrimary;
        }
        if (states.contains(WidgetState.disabled)) {
          return colors.textDisabled;
        }
        return colors.textPrimary;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.surfaceBlack;
        }
        return Colors.transparent;
      }),
      dayOverlayColor: WidgetStateProperty.all(
        colors.neutralGray.withValues(alpha: 0.12),
      ),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.textInversePrimary;
        }
        return colors.textPrimary;
      }),
      todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.surfaceBlack;
        }
        return Colors.transparent;
      }),
      todayBorder: BorderSide(color: colors.textPrimary),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.textInversePrimary;
        }
        return colors.textPrimary;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.surfaceBlack;
        }
        return Colors.transparent;
      }),
      yearOverlayColor: WidgetStateProperty.all(
        colors.neutralGray.withValues(alpha: 0.12),
      ),
      weekdayStyle: TextStyle(color: colors.textSecondary),
      cancelButtonStyle: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(colors.textPrimary),
      ),
      confirmButtonStyle: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(colors.textPrimary),
      ),
      dividerColor: colors.borderDivider,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.allLg),
    );
  }

  static PageTransitionsTheme pageTransitionsTheme() =>
      const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      );
}
