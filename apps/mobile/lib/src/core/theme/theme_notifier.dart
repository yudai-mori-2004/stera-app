import "package:stera/src/services/kv_store/kv_store.dart";
import "package:flutter/material.dart";

class ThemeNotifier {
  static final ThemeNotifier _instance = ThemeNotifier._internal();
  factory ThemeNotifier() => _instance;
  ThemeNotifier._internal();

  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  Future<void> loadThemeMode() async {
    final savedTheme = KvStore.get<String>(KvStoreKeys.themeMode);

    if (savedTheme == null) {
      themeModeNotifier.value = ThemeMode.system;
      return;
    }

    if (savedTheme == ThemeMode.light.name) {
      themeModeNotifier.value = ThemeMode.light;
    } else if (savedTheme == ThemeMode.dark.name) {
      themeModeNotifier.value = ThemeMode.dark;
    } else {
      themeModeNotifier.value = ThemeMode.system;
    }
  }

  void toggleTheme() {
    if (themeModeNotifier.value == ThemeMode.light) {
      themeModeNotifier.value = ThemeMode.dark;
    } else if (themeModeNotifier.value == ThemeMode.dark) {
      themeModeNotifier.value = ThemeMode.light;
    } else {
      final platformBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      themeModeNotifier.value = platformBrightness == Brightness.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    }
    saveThemePreference(themeModeNotifier.value);
  }

  void setThemeMode(ThemeMode mode) {
    themeModeNotifier.value = mode;
    saveThemePreference(mode);
  }

  Future<void> saveThemePreference(ThemeMode mode) async {
    await KvStore.set(KvStoreKeys.themeMode, mode.name);
  }
}
