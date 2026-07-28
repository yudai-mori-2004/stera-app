import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

class AppSliderDialog {
  static void showAppSliderDialog({
    required BuildContext context,
    required Widget content,
    ShapeDecoration? decoration,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 500),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // Use different curves for opening vs closing
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeIn, // Faster curve for closing
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
              child: Material(
                color: Colors.transparent,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                clipBehavior: Clip.antiAlias,
                elevation: 0,
                child: Container(
                  decoration:
                      decoration ??
                      ShapeDecoration(
                        color: context.colors.surfaceSecondary,
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          // Hairline in dark mode: shadows don't read on dark
                          // surfaces, so the edge carries the elevation.
                          side: context.isDarkMode
                              ? BorderSide(color: context.colors.borderDivider)
                              : BorderSide.none,
                        ),
                      ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
