import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/theme_notifier.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class ThemeModeBottomSheet extends StatefulWidget {
  const ThemeModeBottomSheet({super.key});

  @override
  State<ThemeModeBottomSheet> createState() => _ThemeModeBottomSheetState();
}

class _ThemeModeBottomSheetState extends State<ThemeModeBottomSheet> {
  ThemeMode _selectedThemeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedThemeMode = ThemeNotifier().themeModeNotifier.value;
      });
    });
  }

  String _labelFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return "System";
      case ThemeMode.light:
        return "Light";
      case ThemeMode.dark:
        return "Dark";
    }
  }

  @override
  Widget build(BuildContext context) {
    // A [Material], not a decorated [Container]: the rows are [ListTile]s, and
    // a tile paints its background and ink splash onto the nearest Material
    // ancestor — a plain box in between hides both and trips an assertion.
    return Material(
      color: context.colors.surfaceSecondary,
      clipBehavior: Clip.antiAlias,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Container(
        width: context.w,
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(
                "Appearance",
                style: context.textTheme.headMd.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ThemeMode.values.reversed
                  .map(
                    (themeMode) => ListTile(
                      onTap: () {
                        ThemeNotifier().setThemeMode(themeMode);

                        setState(() {
                          _selectedThemeMode = themeMode;
                        });
                      },
                      title: Text(
                        "${_labelFor(themeMode)} theme",
                        style: context.textTheme.bodySmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      trailing: _selectedThemeMode == themeMode
                          ? Icon(Icons.check, color: context.colors.blue)
                          : const SizedBox(width: AppSpacing.xl),
                    ),
                  )
                  .toList(),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ],
        ),
      ),
    );
  }
}
