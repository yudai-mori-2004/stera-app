import "package:flutter/services.dart";

/// Status-bar icon styling for a given app [brightness].
///
/// The two fields look contradictory because they are: `statusBarBrightness` is
/// iOS and describes the *background* behind the bar, while
/// `statusBarIconBrightness` is Android and describes the *icons* themselves. For
/// a dark app surface iOS wants `.dark` and Android wants `.light` — both meaning
/// "light icons".
SystemUiOverlayStyle systemOverlayStyleFor(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: const Color(0x00000000),
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );
}
