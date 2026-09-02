import "dart:async";

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:google_sign_in/google_sign_in.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/common/utils/app_url_launcher.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_button/app_button.dart";
import "package:stera/src/core/common/widgets/app_button/enums/button_type.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/config/constants/app_constants.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/data/models/app_auth_type.dart";
import "package:stera/src/modules/auth/data/repo/auth_repo.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/home/ui/navigation_page.dart";
import "package:stera/src/modules/onboarding/ui/onboarding_page.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/config/constants/brand.dart";

class LoginModal extends StatefulWidget {
  const LoginModal({super.key});

  @override
  State<LoginModal> createState() => _LoginModalState();
}

class _LoginModalState extends State<LoginModal> {
  StreamSubscription? _authSubscription;
  final ValueNotifier<bool> _googleLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _appleLoadingNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authSubscription = AuthRepo.googleSignIn.authenticationEvents.listen(
        (event) async {
          if (!mounted) return;

          switch (event) {
            case GoogleSignInAuthenticationEventSignIn():
              final ap = context.read<AuthProvider>();
              _googleLoadingNotifier.value = true;

              final error = await ap.onAuth(
                type: AppAuthType.google,
                event: event,
              );
              _googleLoadingNotifier.value = false;

              if (error != null) {
                AppToast.show(title: error.message);
                return;
              }

              _routeAfterAuth(ap);
            case GoogleSignInAuthenticationEventSignOut():
              _googleLoadingNotifier.value = false;
          }
        },
        onError: (Object error) {
          AuthRepo.markGoogleAuthCompleted();
          if (!mounted) return;
          _googleLoadingNotifier.value = false;
          if (error is GoogleSignInException &&
              error.code == GoogleSignInExceptionCode.canceled) {
            return;
          }
          AppToast.show(title: "Google sign-in failed. Please try again.");
        },
      );
    });
  }

  void _routeAfterAuth(AuthProvider ap) {
    if (ap.isNewUser) {
      AppRouter.replace(OnboardingPage.routeName);
      return;
    }
    AppRouter.replace(NavigationPage.routeName);
  }

  Future<void> _handleAppleSignIn() async {
    final ap = context.read<AuthProvider>();
    _appleLoadingNotifier.value = true;

    final error = await ap.onAuth(type: AppAuthType.apple);
    _appleLoadingNotifier.value = false;

    if (!mounted) return;

    if (error != null) {
      AppToast.show(title: error.message);
      return;
    }

    _routeAfterAuth(ap);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _googleLoadingNotifier.dispose();
    _appleLoadingNotifier.dispose();
    super.dispose();
  }

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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpacing.lgPlus),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                        const TextSpan(text: "Build with "),
                        TextSpan(
                          text: "multimodal data",
                          style: context.textTheme.head3XlHandjet,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    Brand.loginTagline,
                    textAlign: TextAlign.left,
                    style: context.textTheme.bodyMdMedium.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lgPlus),
                  ValueListenableBuilder<bool>(
                    valueListenable: _googleLoadingNotifier,
                    builder: (_, loading, _) {
                      return AppButton(
                        type: ButtonType.primary,
                        text: "Continue with Google",
                        leadingIcon: SvgPicture.asset(
                          AppAssets.googleIcon,
                          width: 20,
                          height: 20,
                        ),
                        isLoading: loading,
                        isDisabled: loading,
                        onPressed: () async {
                          if (_googleLoadingNotifier.value) return;
                          HapticFeedback.lightImpact();
                          _googleLoadingNotifier.value = true;
                          await AuthRepo.authenticateWithGoogle();
                          if (mounted && !AuthRepo.isGoogleAuthInFlight) {
                            _googleLoadingNotifier.value = false;
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ValueListenableBuilder<bool>(
                    valueListenable: _appleLoadingNotifier,
                    builder: (_, loading, _) {
                      return AppButton(
                        type: ButtonType.secondary,
                        text: "Continue with Apple",
                        isLoading: loading,
                        isDisabled: loading,
                        leadingIcon: Icon(
                          Icons.apple,
                          size: 20,
                          color: context.colors.textPrimary,
                        ),
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          await _handleAppleSignIn();
                        },
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lgPlus),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        style: context.textTheme.bodyXs.copyWith(
                          color: context.colors.textSecondary,
                        ),
                        children: [
                          const TextSpan(
                            text: "By continuing, you agree to our ",
                          ),
                          TextSpan(
                            text: "T&C",
                            style: context.textTheme.bodyXs.copyWith(
                              decoration: TextDecoration.underline,
                              color: context.colors.blue,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => AppUrlLauncher.launchUrl(
                                AppConstants.termsAndConditions,
                              ),
                          ),
                          const TextSpan(text: " and "),
                          TextSpan(
                            text: "Privacy Policy",
                            style: context.textTheme.bodyXs.copyWith(
                              decoration: TextDecoration.underline,
                              color: context.colors.blue,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => AppUrlLauncher.launchUrl(
                                AppConstants.privacyPolicy,
                              ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
