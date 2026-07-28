import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/modules/capture/ui/capture_page.dart";
import "package:stera/src/modules/recordings/providers/recordings_provider.dart";
import "package:stera_recorder/stera_recorder.dart";

/// The regression test that matters most for `NO_AUTH_MODE`: the capture shell
/// is pumped with **only** the providers `main.dart` registers in that build, so
/// a `context.read<AuthProvider>()` (or `UploadProvider`, or
/// `UploadedVideosProvider`) sneaking onto this path fails here rather than on a
/// user's device, where it would surface as a red screen on launch.
void main() {
  setUp(() {
    AppConfig.debugOverrideNoAuthMode = true;
  });

  tearDown(() {
    AppConfig.debugOverrideNoAuthMode = null;
  });

  Widget host() {
    final router = GoRouter(
      initialLocation: CapturePage.routeName,
      routes: [
        GoRoute(
          path: CapturePage.routeName,
          builder: (_, _) => const CapturePage(),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ArRecorderProvider(
            // The real `KvStoreRecorderPreferences` reads `KvStore`, which
            // isn't initialised under `flutter test`.
            preferences: InMemoryRecorderPreferences(),
            permissions: const _DeniedRecorderPermissions(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => RecordingsProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets("builds with only the no-auth providers in the tree", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CapturePage), findsOneWidget);
  });

  testWidgets("offers the record action and the recordings section", (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text("Start Recording"), findsOneWidget);
    expect(find.text("Recordings"), findsOneWidget);
  });

  testWidgets("shows no upload or account surfaces", (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    for (final label in ["Submit", "Upload", "Library", "Log out", "Profile"]) {
      expect(find.text(label), findsNothing, reason: "for '$label'");
    }
  });
}

/// The recorder only ever *checks* permission; nothing on this page opens a
/// session, so denying is both accurate and inert.
class _DeniedRecorderPermissions implements RecorderPermissions {
  const _DeniedRecorderPermissions();

  @override
  Future<bool> isCameraPermissionGranted() async => false;

  @override
  Future<bool> openSettings() async => false;
}
