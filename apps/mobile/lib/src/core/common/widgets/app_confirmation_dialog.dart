import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/spring_entrance.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";

/// Design-system confirmation dialog: a superellipse card on
/// [C.surfaceSecondary] with a hairline border in dark mode (shadows don't
/// read on dark surfaces, so the edge carries the elevation), the safe action
/// on top and the confirming action below. Pops `true` on confirm, `false`
/// on cancel.
///
/// [isDestructive] paints the confirm button red — use for deletes and
/// discards. Otherwise the confirm button is a standard primary.
class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    this.isDestructive = false,
  });

  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final bool isDestructive;

  /// Shows the dialog and resolves to whether the user confirmed. Dismissing
  /// the barrier counts as cancel.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    required String cancelText,
    bool isDestructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmationDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        isDestructive: isDestructive,
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.surfaceSecondary,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(AppRadii.lgPlus),
        side: context.isDarkMode
            ? BorderSide(color: colors.borderDivider)
            : BorderSide.none,
      ),
      child: SpringEntrance(
        beginOffset: Offset.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.textTheme.headXl.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                style: context.textTheme.bodyMd.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                text: cancelText,
                type: ButtonType.secondary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                text: confirmText,
                type: ButtonType.primary,
                backgroundColor: isDestructive ? colors.red : null,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
