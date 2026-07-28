import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_slider_dialog.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/auth/ui/widgets/name_onboarding_modal.dart";
import "package:stera/src/modules/onboarding/providers/onboarding_provider.dart";
import "package:stera/src/modules/onboarding/ui/widgets/country_selector_modal.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class OnboardingPage extends StatefulWidget {
  static const routeName = "/onboarding";
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ap = context.read<AuthProvider>();
      final pendingName = ap.pendingDisplayName;

      if (pendingName != null && pendingName.isNotEmpty) {
        // Apple already provided the user's name — skip the name modal and go
        // straight to country selection (Apple HIG requirement).
        context.read<OnboardingProvider>().nameController.text = pendingName;
        AppSliderDialog.showAppSliderDialog(
          context: context,
          content: const CountrySelectorModal(),
        );
        return;
      }

      AppSliderDialog.showAppSliderDialog(
        context: context,
        content: const NameOnboardingModal(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceTertiary,
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(AppAssets.texture),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
