import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_sizes.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/app_slider_dialog.dart";
import "package:stera/src/core/common/widgets/app_text_field/app_text_field.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/auth/ui/login_page.dart";
import "package:stera/src/modules/onboarding/providers/onboarding_provider.dart";
import "package:stera/src/modules/onboarding/ui/widgets/country_selector_modal.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:provider/provider.dart";

class NameOnboardingModal extends StatelessWidget {
  const NameOnboardingModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.w,
      decoration: ShapeDecoration(
        color: context.colors.surfaceSecondary,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.25,
                  child: SvgPicture.asset(AppAssets.lines, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            behavior: HitTestBehavior.opaque,
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpacing.lgPlus),
              child: Consumer<OnboardingProvider>(
                builder: (context, op, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (AppConfig.allowDebugFeatures)
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppButton(
                            width: 76,
                            text: "Log out",
                            type: ButtonType.tertiary,
                            size: ButtonSizes.sm,
                            showShadow: false,
                            onPressed: () async {
                              FocusScope.of(context).unfocus();
                              final ap = context.read<AuthProvider>();
                              await ap.logout();
                              if (!context.mounted) return;
                              op.reset();
                              AppRouter.replace(LoginPage.routeName);
                            },
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.xlPlus),
                          image: DecorationImage(
                            image: AssetImage(AppAssets.logoAsset(context)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lgPlus),
                      Text.rich(
                        TextSpan(
                          style: context.textTheme.head3XlGaramond,
                          children: [
                            const TextSpan(text: "What should we "),
                            TextSpan(
                              text: "call you?",
                              style: context.textTheme.head3XlHandjet,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        "Tell us your name so we can personalize your experience",
                        style: context.textTheme.bodyMdMedium.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lgPlus),
                      AppTextField(
                        // Only field on the sheet, and there's nothing else to
                        // do here — don't make the user tap to start typing.
                        autofocus: true,
                        hintText: "Enter your name",
                        controller: op.nameController,
                        header: "Name",
                      ),
                      const SizedBox(height: AppSpacing.lgPlus),
                      ListenableBuilder(
                        listenable: op.nameController,
                        builder: (context, _) {
                          final isEnabled = op.nameController.text
                              .trim()
                              .isNotEmpty;
                          return AppButton(
                            text: "Continue",
                            isDisabled: !isEnabled,
                            onPressed: !isEnabled
                                ? null
                                : () async {
                                    FocusScope.of(context).unfocus();
                                    Navigator.of(context).pop();
                                    WidgetsBinding.instance.addPostFrameCallback((
                                      _,
                                    ) {
                                      final ctx =
                                          AppRouter.navigatorKey.currentContext;
                                      if (ctx == null) return;
                                      AppSliderDialog.showAppSliderDialog(
                                        context: ctx,
                                        content: CountrySelectorModal(
                                          onBack: () {
                                            final backCtx = AppRouter
                                                .navigatorKey
                                                .currentContext;
                                            if (backCtx == null) return;
                                            AppSliderDialog.showAppSliderDialog(
                                              context: backCtx,
                                              content:
                                                  const NameOnboardingModal(),
                                            );
                                          },
                                        ),
                                      );
                                    });
                                  },
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
