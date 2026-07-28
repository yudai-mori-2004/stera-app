import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/app_slider_dialog.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/auth/ui/widgets/login_modal.dart";
import "package:flutter/material.dart";

class LoginPage extends StatefulWidget {
  static const String routeName = "/login";
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSliderDialog.showAppSliderDialog(
        context: context,
        content: const LoginModal(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceTertiary,
      body: Container(
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
