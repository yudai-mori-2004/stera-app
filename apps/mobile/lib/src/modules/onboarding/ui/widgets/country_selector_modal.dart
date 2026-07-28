import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_text_field/app_text_field.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/auth/ui/login_page.dart";
import "package:stera/src/modules/onboarding/data/enums/country.dart";
import "package:stera/src/modules/home/ui/navigation_page.dart";
import "package:stera/src/modules/onboarding/providers/onboarding_provider.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:provider/provider.dart";
import "package:solar_icons/solar_icons.dart";

class CountrySelectorModal extends StatelessWidget {
  const CountrySelectorModal({
    super.key,
    this.onBack,
  });

  final VoidCallback? onBack;

  /// True when the user reached this step with a prefilled name (e.g. Sign in with Apple).

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.w,
      height: context.h * 0.65,
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
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lgPlus),
            child: Consumer<OnboardingProvider>(
              builder: (context, op, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      height: constraints.maxHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (onBack != null) ...[
                            IconButton(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                AppRouter.pop();
                                onBack!();
                              },
                              icon: Icon(
                                SolarIconsOutline.arrowLeft,
                                color: context.colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          Text(
                            "Select your country",
                            style: context.textTheme.head3XlHandjet,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            "Choose your country to set your contributor profile.",
                            style: context.textTheme.bodyMdMedium.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: Country.values.map((country) {
                                  final isSelected =
                                      op.selectedCountry == country;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                    child: Pressable(
                                      pressedScale: 0.97,
                                      onTap: () {
                                        op.selectedCountry = country;
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.mdPlus,
                                          vertical: AppSpacing.md,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? context.colors.surfaceTertiary
                                              : context.colors.surfaceSecondary,
                                          borderRadius: AppRadii.allMd,
                                          border: Border.all(
                                            color: isSelected
                                                ? context.colors.blue
                                                : context.colors.borderDefault,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              country.flag,
                                              style: context
                                                  .textTheme
                                                  .bodyMdMedium,
                                            ),
                                            const SizedBox(width: AppSpacing.smPlus),
                                            Expanded(
                                              child: Text(
                                                country.name,
                                                style: context
                                                    .textTheme
                                                    .bodySmMedium
                                                    .copyWith(
                                                      color: context
                                                          .colors
                                                          .textPrimary,
                                                    ),
                                              ),
                                            ),
                                            Text(
                                              country.code,
                                              style: context.textTheme.bodyXs
                                                  .copyWith(
                                                    color: context
                                                        .colors
                                                        .textSecondary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          if (op.selectedCountry == Country.other) ...[
                            const SizedBox(height: AppSpacing.sm),
                            AppTextField(
                              controller: op.customCountryController,
                              header: "Custom country",
                              hintText: "Enter your country name",
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          AppButton(
                            text: "Submit",
                            isLoading: op.isLoading,
                            isDisabled: op.isLoading,
                            onPressed: op.isLoading
                                ? null
                                : () async {
                                    FocusScope.of(context).unfocus();
                                    final ap = context.read<AuthProvider>();

                                    final validationErr = op
                                        .validateOnboardingData();
                                    if (validationErr != null) {
                                      AppToast.show(
                                        title: validationErr.message,
                                      );
                                      return;
                                    }

                                    if (!context.mounted) return;

                                    final (user, err) = await op.onboardUser();
                                    if (err != null) {
                                      AppToast.show(title: err.message);
                                      if (err.code == ErrorType.unauthorized) {
                                        await ap.logout();
                                        if (!context.mounted) return;
                                        AppRouter.replace(LoginPage.routeName);
                                      }
                                      return;
                                    }

                                    if (user == null || !context.mounted) {
                                      return;
                                    }

                                    if (!context.mounted) return;

                                    ap.user = user;
                                    ap.isNewUser = false;
                                    ap.pendingDisplayName = null;
                                    // Clearing `isNewUser` + setting the user
                                    // makes the redirect resolve to root; go()
                                    // also dismisses this modal.
                                    AppRouter.replace(NavigationPage.routeName);
                                  },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
