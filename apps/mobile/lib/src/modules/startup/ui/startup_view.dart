import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/common/widgets/spring_scroll_physics.dart";
import "package:stera/src/core/common/widgets/value_listenable_builder2.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/core/router/app_routes.dart";
import "package:stera/src/core/theme/app_theme.dart";
import "package:stera/src/core/theme/system_ui.dart";
import "package:stera/src/core/theme/theme_notifier.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/startup/data/app_state.dart";
import "package:stera/src/modules/startup/ui/splash_view.dart";
import "package:stera/src/modules/startup/ui/startup_error_view.dart";
import "package:stera/src/modules/startup/view_models/startup_view_model.dart";
import "package:stera/src/services/upload_service/lifecycle/upload_app_lifecycle_handler.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";

/// Root widget. Owns the [StartupViewModel] and renders the cold-boot
/// [AppState]: a splash or error shell while bootstrap runs, then the routed
/// app. It also carries the app-lifecycle duties that used to live in
/// `SteraApp`.
///
/// The router (`MaterialApp.router`) is mounted **only after** bootstrap
/// succeeds — the redirect reads `AuthProvider` synchronously, so building it
/// earlier would resolve to a route (e.g. login) before the session is known.
class StartupView extends StatefulWidget {
  const StartupView({super.key});

  /// Re-runs the cold-boot path (splash → guarded re-init → root). Used by the
  /// forced-update flow, which isn't an auth change and so can't rely on the
  /// router's reactive redirect. Auth-driven flows (login, logout, onboarding)
  /// no longer call this — they change `AuthProvider` state and let the router's
  /// `refreshListenable` redirect. No-op if the root view isn't mounted.
  static void restart() => _activeState?._restart();

  static _StartupViewState? _activeState;

  @override
  State<StartupView> createState() => _StartupViewState();
}

class _StartupViewState extends State<StartupView> with WidgetsBindingObserver {
  late final StartupViewModel _viewModel;
  bool _toastInitialized = false;

  @override
  void initState() {
    super.initState();
    // `AuthProvider` isn't registered in a no-auth build, so reading it here
    // would throw `ProviderNotFoundException` before the first frame.
    final authProvider = AppConfig.noAuthMode
        ? null
        : context.read<AuthProvider>();

    _viewModel = StartupViewModel(authProvider: authProvider);
    StartupView._activeState = this;

    // Build the router with the auth provider as its `refreshListenable` so
    // login / logout / onboarding redirects run reactively off auth state.
    // Null in no-auth mode, where there is no redirect to refresh.
    AppRouter.init(authProvider);

    WidgetsBinding.instance.addObserver(this);
    UploadAppLifecycleHandler.onColdStart();

    _viewModel.initializeApp();
  }

  @override
  void dispose() {
    if (StartupView._activeState == this) StartupView._activeState = null;
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  /// Re-runs bootstrap, then re-enters at the root so the router's redirect
  /// resolves against the restored auth state. Mirrors the old `SplashPage`
  /// warm re-init, but without a dedicated route.
  Future<void> _restart() async {
    await _viewModel.initializeApp();
    if (!mounted) return;
    AppRouter.replace(AppRoutes.initialLocation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    UploadAppLifecycleHandler.handleState(state);
  }

  /// Wires toasts to the router's navigator once — right after the router
  /// first mounts (i.e. when bootstrap completes).
  void _ensureToastInitialized() {
    if (_toastInitialized) return;
    _toastInitialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppToast.init(key: AppRouter.navigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder2<AppState, ThemeMode>(
      valueListenable: _viewModel.appStateNotifier,
      valueListenable2: ThemeNotifier().themeModeNotifier,
      builder: (context, appState, themeMode, _) {
        return switch (appState) {
          InitializingApp() => _shell(themeMode, const SplashView()),
          AppInitializationError() => _shell(
            themeMode,
            StartupErrorView(onRetry: _viewModel.retryInitialization),
          ),
          AppInitialized() => _routedApp(themeMode),
        };
      },
    );
  }

  /// A minimal, router-less [MaterialApp] used for the splash/error screens so
  /// they get theming without triggering route resolution.
  Widget _shell(ThemeMode themeMode, Widget home) {
    return MaterialApp(
      key: const ValueKey("startup-shell"),
      debugShowCheckedModeBanner: false,
      title: "Stera by FPV Labs",
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: _appBuilder,
      home: home,
    );
  }

  Widget _routedApp(ThemeMode themeMode) {
    _ensureToastInitialized();
    return MaterialApp.router(
      key: const ValueKey("startup-router"),
      debugShowCheckedModeBanner: false,
      title: "Stera by FPV Labs",
      routerConfig: AppRouter.router,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: _appBuilder,
      // Every scrollable bounces back on the app's shared spring.
      scrollBehavior: const SpringScrollBehavior(),
    );
  }

  /// Wraps every screen in both apps.
  ///
  /// - Clamps text scaling. The app's dense surfaces (AR overlays, stat rows)
  ///   have fixed-height boxes that overflow well before the 2.0+ the OS allows;
  ///   [_maxTextScale] keeps large-text users legible without breaking layout.
  /// - Publishes the status-bar style, which otherwise never tracks the app's
  ///   light/dark toggle.
  static Widget _appBuilder(BuildContext context, Widget? child) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyleFor(Theme.of(context).brightness),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTextScale,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  /// Chosen over the more common 1.3 because accessibility text is a real use
  /// case here, not a stress test; raise it once the dense surfaces are audited.
  static const double _maxTextScale = 1.4;
}
