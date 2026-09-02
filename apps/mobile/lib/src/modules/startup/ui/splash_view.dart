import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/config/constants/brand.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";

/// The branded splash visual (logo + spinner), with a fade-in on mount.
///
/// Pure UI: it owns no bootstrap or navigation logic so it can be rendered both
/// by the cold-boot [StartupView] overlay and by the warm re-init splash route.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceTertiary,
      body: Container(
        width: context.w,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(AppAssets.texture),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Image(
                      image: AssetImage(AppAssets.logoAsset(context)),
                      width: 200,
                      height: 84,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const CupertinoActivityIndicator(radius: 12),
                  ),
                ],
              ),
            ),
            FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                child: Column(
                  children: [
                    Text(Brand.splashTitle, style: context.textTheme.head3XlGaramond),
                    Text(Brand.splashSubtitle, style: context.textTheme.bodyXs),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
