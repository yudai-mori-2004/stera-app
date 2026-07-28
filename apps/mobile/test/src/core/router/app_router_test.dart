import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/ui/login_page.dart";
import "package:stera/src/modules/capture/ui/capture_page.dart";
import "package:stera/src/modules/home/ui/navigation_page.dart";
import "package:stera/src/modules/recordings/providers/recordings_provider.dart";
import "package:stera_recorder/stera_recorder.dart";

void main() {
  setUp(() {
    AppConfig.debugOverrideNoAuthMode = true;
    AppRouter.debugReset();
  });

  tearDown(() {
    AppConfig.debugOverrideNoAuthMode = null;
    AppRouter.debugReset();
  });

  testWidgets(
    "in no-auth mode the root route lands on the capture shell, with no "
    "redirect reading AuthProvider",
    (tester) async {
      // A null `refreshListenable` is what `StartupView` passes in this build.
      AppRouter.init(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ArRecorderProvider(
                preferences: InMemoryRecorderPreferences(),
                permissions: const _DeniedRecorderPermissions(),
              ),
            ),
            ChangeNotifierProvider(create: (_) => RecordingsProvider()),
          ],
          child: MaterialApp.router(routerConfig: AppRouter.router),
        ),
      );
      await tester.pump();

      // The redirect is null rather than short-circuiting, so GoRouter never
      // calls `context.read<AuthProvider>()` — which isn't registered here and
      // would throw `ProviderNotFoundException` on the first navigation.
      expect(tester.takeException(), isNull);
      expect(find.byType(CapturePage), findsOneWidget);
      expect(find.byType(NavigationPage), findsNothing);
      expect(find.byType(LoginPage), findsNothing);
    },
  );
}

class _DeniedRecorderPermissions implements RecorderPermissions {
  const _DeniedRecorderPermissions();

  @override
  Future<bool> isCameraPermissionGranted() async => false;

  @override
  Future<bool> openSettings() async => false;
}
