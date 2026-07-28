import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/app_text_field/app_text_field.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class DeleteAccountBottomsheet extends StatefulWidget {
  const DeleteAccountBottomsheet({super.key});

  @override
  State<DeleteAccountBottomsheet> createState() =>
      _DeleteAccountBottomsheetState();
}

class _DeleteAccountBottomsheetState extends State<DeleteAccountBottomsheet> {
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  final TextEditingController confirmationController = TextEditingController();

  /// Check if confirmation text matches "DELETE" exactly
  bool get isDeleteConfirmed => confirmationController.text.trim() == "DELETE";

  @override
  void dispose() {
    loadingNotifier.dispose();
    confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        color: context.colors.surfacePrimary,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Warning icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.colors.red,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  color: context.colors.surfacePrimary,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Title
              Text(
                "Permanently delete account?",
                style: context.textTheme.head2Xl,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              // Description
              Text(
                "Once you delete your account, all your videos and progress are gone forever.\nWe'll miss you… but we respect your choice ❤️",
                style: context.textTheme.bodySm.copyWith(
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              // Confirmation text field
              AppTextField(
                controller: confirmationController,
                hintText: "Type DELETE to confirm",
                description: "Type DELETE to confirm deletion",
                onChanged: (_) {
                  setState(() {}); // Rebuild to update button state
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              // Buttons row
              ValueListenableBuilder(
                valueListenable: loadingNotifier,
                builder: (_, loading, _) {
                  return Row(
                    children: [
                      // Delete Account button
                      Expanded(
                        child: AppButton(
                          text: "Delete Account",
                          type: ButtonType.secondary,
                          height: 56,
                          backgroundColor: context.colors.surfacePrimary,
                          foregroundColor: context.colors.textPrimary,
                          borderColor: context.colors.textTertiary,
                          showShadow: false,
                          isLoading: loading,
                          isDisabled: loading || !isDeleteConfirmed,
                          onPressed: (loading || !isDeleteConfirmed)
                              ? null
                              : () async {
                                  loadingNotifier.value = true;
                                  final ap = context.read<AuthProvider>();
                                  final err = await ap.delete();
                                  loadingNotifier.value = false;

                                  if (err != null) {
                                    AppToast.show(title: err.message);
                                  } else {
                                    AppRouter.pop();
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // Cancel button
                      Expanded(
                        child: AppButton(
                          text: "Cancel",
                          type: ButtonType.primary,
                          height: 56,
                          showShadow: false,
                          isDisabled: loading,
                          onPressed: loading ? null : () => AppRouter.pop(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
