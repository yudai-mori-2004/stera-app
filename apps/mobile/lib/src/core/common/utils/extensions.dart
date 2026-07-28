import "package:stera/src/core/theme/app_text_theme.dart";
import "package:stera/src/core/theme/colors.dart";
import "package:flutter/material.dart";

extension ThemeX on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  C get colors => isDarkMode ? C.dark() : C.light();
  C get inverseColors => isDarkMode ? C.light() : C.dark();

  AppTextTheme get textTheme => AppTextTheme.fromColors(colors);

  C get darkColors => C.dark();
  AppTextTheme get darkTextTheme => AppTextTheme.fromColors(darkColors);
}

extension SizeX on BuildContext {
  // `sizeOf` rather than `MediaQuery.of`: the latter subscribes to every
  // MediaQuery change, so these rebuild on each keyboard open.
  double get h => MediaQuery.sizeOf(this).height;
  double get w => MediaQuery.sizeOf(this).width;
  bool get isSmallSized => MediaQuery.sizeOf(this).height < 700;
}

extension TextStyleX on TextStyle {
  /// Fixed-width digits. Use on any number that updates in place — timers,
  /// percentages, byte counts — so the text doesn't jitter as digits change.
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

extension NavigationX on BuildContext {
  void popUntil({String? routeName}) => Navigator.of(this).popUntil(
    (route) => routeName != null
        ? route.currentResult == routeName || route.isFirst
        : route.isFirst,
  );
}
