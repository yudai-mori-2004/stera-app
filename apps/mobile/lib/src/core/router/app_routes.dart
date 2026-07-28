import "package:stera/src/core/common/widgets/spring_page_transition.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/modules/ar_recorder/ui/ar_recorder_page.dart";
import "package:stera/src/modules/auth/ui/login_page.dart";
import "package:stera/src/modules/capture/ui/capture_page.dart";
import "package:stera/src/modules/home/ui/navigation_page.dart";
import "package:stera/src/modules/profile/ui/profile_page.dart";
import "package:stera/src/modules/onboarding/ui/onboarding_page.dart";
import "package:stera/src/modules/mcap_preview/ui/mcap_preview_page.dart";
import "package:stera/src/modules/demo/ui/demo_video_fullscreen_page.dart";
import "package:go_router/go_router.dart";

class AppRoutes {
  // Cold boot lands here; `StartupView` overlays the splash while bootstrap
  // runs, then the redirect below routes to login/onboarding as needed. Warm
  // re-init (logout, update, account change) re-runs the same cold-boot path
  // via `StartupView.restart()` — there is no dedicated splash route.
  static const String initialLocation = NavigationPage.routeName;

  static const List<String> publicRoutes = [
    LoginPage.routeName,
    OnboardingPage.routeName,
  ];

  static final List<RouteBase> routes = [
    GoRoute(
      path: LoginPage.routeName,
      name: LoginPage.routeName,
      pageBuilder: (context, state) =>
          springPage(key: state.pageKey, child: const LoginPage()),
    ),
    GoRoute(
      path: OnboardingPage.routeName,
      name: OnboardingPage.routeName,
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: DemoVideoFullscreenPage.routeName,
      name: DemoVideoFullscreenPage.routeName,
      builder: (context, state) => const DemoVideoFullscreenPage(),
    ),
    // Same path in both builds, so every existing `AppRouter.push("/root")` and
    // `router.go("/root")` call site keeps resolving; only the shell differs.
    GoRoute(
      path: NavigationPage.routeName,
      name: NavigationPage.routeName,
      builder: (context, state) =>
          AppConfig.noAuthMode ? const CapturePage() : const NavigationPage(),
    ),
    GoRoute(
      path: ProfilePage.routeName,
      name: ProfilePage.routeName,
      builder: (context, state) => const ProfilePage(),
    ),
    GoRoute(
      path: ArRecorderPage.routeName,
      name: ArRecorderPage.routeName,
      pageBuilder: (context, state) =>
          springPage(key: state.pageKey, child: const ArRecorderPage()),
    ),
    // Normally pushed with a raw Navigator from the recordings list;
    // registered so the route name resolves for observers/redirects.
    // Requires the session dir as `extra`.
    GoRoute(
      path: McapPreviewPage.routeName,
      name: McapPreviewPage.routeName,
      builder: (context, state) =>
          McapPreviewPage(sessionDir: state.extra as String? ?? ""),
    ),
  ];
}
