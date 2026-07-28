import "package:stera/src/core/router/app_routes.dart";
import "package:stera/src/core/router/demo_inline_video_route_observer.dart";
import "package:stera/src/core/common/utils/app_update.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/home/data/enums/current_page.dart";
import "package:stera/src/modules/home/providers/navigation_provider.dart";
import "package:stera/src/modules/home/ui/navigation_page.dart";
import "package:stera/src/modules/auth/ui/login_page.dart";
import "package:stera/src/modules/onboarding/ui/onboarding_page.dart";
import "package:flutter/widgets.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "dart:developer" as dev;

class AppRouter {
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  static GoRouter? _router;

  /// Builds the singleton router, wiring [authListenable] as the redirect's
  /// `refreshListenable`. Auth transitions (login, logout, onboarding
  /// completion) then re-run the redirect reactively — those flows navigate by
  /// changing auth state, not by imperative routing. Idempotent: only the first
  /// call builds. Call once before the router is first read (see `StartupView`).
  static void init(Listenable? authListenable) {
    _router ??= _build(authListenable);
  }

  static GoRouter get router => _router ??= _build(null);

  /// Drops the memoised router so a test can build a fresh one.
  @visibleForTesting
  static void debugReset() => _router = null;

  static GoRouter _build(Listenable? refreshListenable) => GoRouter(
    initialLocation: AppRoutes.initialLocation,
    routes: AppRoutes.routes,
    navigatorKey: _navigatorKey,
    refreshListenable: refreshListenable,
    observers: AppConfig.noAuthMode
        ? [demoInlineVideoRouteObserver]
        : [
            AppUpdateObserver(),
            demoInlineVideoRouteObserver,
          ],
    // A null redirect is deliberate rather than an early-returning closure:
    // GoRouter skips the callback entirely, so there is no
    // `context.read<AuthProvider>()` on any navigation in a build where that
    // provider isn't registered. A throw inside a redirect surfaces as a
    // permanent error page, i.e. a dead app, so this has to be structurally
    // impossible, not conditionally avoided.
    redirect: AppConfig.noAuthMode ? null : _authRedirect,
  );

  static String? _authRedirect(BuildContext context, GoRouterState state) {
    final ap = context.read<AuthProvider>();
    final location = state.matchedLocation;

    // 1. Handle New User Onboarding (OnboardingToken present but no user data)
    if (ap.isNewUser) {
      if (location == OnboardingPage.routeName) return null;
      dev.log("Router: Redirecting to Onboarding (New User)");
      return OnboardingPage.routeName;
    }

    final isPublicRoute = AppRoutes.publicRoutes.contains(location);

    // 2. Handle Unauthenticated Access
    if (!ap.isLoggedIn) {
      if (isPublicRoute) return null;
      dev.log("Router: Access denied, redirecting to Login");
      return LoginPage.routeName;
    }

    // 3. Handle Redirects away from Public/Onboarding routes for Fully Logged In Users
    if (isPublicRoute) {
      dev.log(
        "Router: Fully authenticated user on terminal route, redirecting to Root",
      );
      return NavigationPage.routeName;
    }

    return null;
  }

  static void push(
    String location, {
    Map<String, dynamic>? extra,
    Map<String, String> queryParams = const {},
    Map<String, String> pathParams = const {},
  }) {
    router.pushNamed(
      location,
      extra: extra,
      queryParameters: queryParams,
      pathParameters: pathParams,
    );
  }

  static void replace(
    String location, {
    Map<String, dynamic>? extra,
    Map<String, String> queryParams = const {},
    Map<String, String> pathParams = const {},
  }) {
    router.goNamed(
      location,
      extra: extra,
      queryParameters: queryParams,
      pathParameters: pathParams,
    );
  }

  static void pop() {
    router.pop();
  }

  static void popUntil() {
    while (router.canPop()) {
      router.pop();
    }
  }

  /// Navigates to the main shell and selects the Upload tab (uploaded videos).
  static void goToUploadTab() {
    router.go(NavigationPage.routeName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      ctx.read<NavigationProvider>().setCurrentPage(CurrentPage.upload);
    });
  }

  static String get currentLocation {
    try {
      final currentConfig = router.routerDelegate.currentConfiguration;
      if (currentConfig.isEmpty) {
        return "";
      }
      final RouteMatch lastMatch = currentConfig.last;
      final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
          ? lastMatch.matches
          : currentConfig;
      return matchList.uri.path;
    } catch (e) {
      return "";
    }
  }

  static bool isOnPublicRoute() {
    final location = currentLocation;
    if (location.isEmpty) {
      return true;
    }
    return AppRoutes.publicRoutes.contains(location);
  }
}

class AppUpdateObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = AppRouter.navigatorKey.currentContext;
      if (context == null) return;

      final location = AppRouter.currentLocation;
      if (location.isNotEmpty) {
        AppUpdate.checkForUpdates(context);
      }
    });
  }
}
