/// Lifecycle of the app's cold-boot bootstrap, driven by
/// `StartupViewModel.appStateNotifier` and rendered by `StartupView`.
sealed class AppState {
  const AppState();
}

/// Bootstrap is running — the splash overlay is shown.
class InitializingApp extends AppState {
  const InitializingApp();
}

/// Bootstrap finished successfully — the routed app is shown.
class AppInitialized extends AppState {
  const AppInitialized();
}

/// Bootstrap threw — the error/retry overlay is shown.
class AppInitializationError extends AppState {
  const AppInitializationError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
