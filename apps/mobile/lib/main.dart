import "package:stera/src/core/common/widgets/app_error_view.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/modules/demo/providers/demo_video_preload_provider.dart";
import "package:stera/src/modules/ar_recorder/adapters/recorder_host_adapters.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/modules/home/providers/navigation_provider.dart";
import "package:stera/src/modules/onboarding/providers/onboarding_provider.dart";
import "package:stera/src/modules/profile/providers/profile_provider.dart";
import "package:stera/src/modules/recordings/providers/recordings_provider.dart";
import "package:stera/src/modules/startup/ui/startup_view.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/modules/uploaded_videos/providers/uploaded_videos_provider.dart";
import "package:flutter/widgets.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:provider/provider.dart";
import "package:provider/single_child_widget.dart";
import "package:stera_recorder/stera_recorder.dart";

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // `.env` must load before anything reads `AppConfig`. Everything else now
  // bootstraps inside `StartupViewModel`.
  try {
    // `isOptional` swallows missing-file and empty-file errors and still marks
    // dotenv initialized, so `dotenv.env` returns {} instead of throwing. A
    // NO_AUTH_MODE build ships a `.env` containing only the flag.
    await dotenv.load(fileName: ".env", isOptional: true);
  } catch (e) {
    // Any other failure (a malformed file, a parser throw) must not cost a boot.
    debugPrint("⚠️ .env load failed; continuing with an empty environment: $e");
    dotenv.loadFromString(envString: "", isOptional: true);
  }

  // Replaces the framework's default error box — governs what the user sees.
  ErrorWidget.builder = (details) => AppErrorView(details: details);

  runApp(
    MultiProvider(
      providers: AppConfig.noAuthMode ? _noAuthProviders() : _appProviders(),
      child: const StartupView(),
    ),
  );
}

/// The recorder provider is the one thing both trees share, so it is built in
/// exactly one place — the two lists below cannot drift apart.
ChangeNotifierProvider<ArRecorderProvider> _arRecorderProvider() =>
    ChangeNotifierProvider(
      create: (context) => ArRecorderProvider(
        preferences: const KvStoreRecorderPreferences(),
        permissions: const AppRecorderPermissions(),
      ),
    );

List<SingleChildWidget> _appProviders() => [
  ChangeNotifierProvider(create: (context) => DemoVideoPreloadProvider()),
  ChangeNotifierProvider(create: (context) => AuthProvider()),
  ChangeNotifierProvider(create: (context) => UploadedVideosProvider()),
  ChangeNotifierProvider(create: (context) => NavigationProvider()),
  ChangeNotifierProvider(create: (context) => OnboardingProvider()),
  ChangeNotifierProvider(create: (context) => UploadProvider()),
  ChangeNotifierProvider(create: (context) => ProfileProvider()),
  _arRecorderProvider(),
  ChangeNotifierProvider(create: (context) => RecordingsProvider()),
];

/// Everything the auth-free capture path can reach, and nothing else.
///
/// The omissions are the point: `UploadProvider`'s constructor is not inert —
/// it opens the Drift DB via `db.watch()`, wires `UploadQueueManager` and
/// schedules `_resumePendingUploadsOnStart()`. `ChangeNotifierProvider` is lazy,
/// so an unread provider would never construct, but relying on that is fragile;
/// leaving them out makes it structural. A widget that reaches for one of these
/// on the no-auth path throws `ProviderNotFoundException` in debug, which is
/// exactly the signal wanted.
List<SingleChildWidget> _noAuthProviders() => [
  // The capture shell shows the demo card, whose fullscreen page reads this.
  // Inert unless `DEMO_VIDEO_URL` is set — otherwise the card shows a still.
  ChangeNotifierProvider(create: (context) => DemoVideoPreloadProvider()),
  _arRecorderProvider(),
  ChangeNotifierProvider(create: (context) => RecordingsProvider()),
];
