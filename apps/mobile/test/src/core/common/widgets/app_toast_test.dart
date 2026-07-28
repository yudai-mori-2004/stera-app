import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";

void main() {
  Future<void> pumpHost(
    WidgetTester tester,
    GlobalKey<NavigatorState> navKey,
  ) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const Scaffold()),
    );
  }

  /// Show → post-frame insert → AnimatedList state change → item renders:
  /// the toast reaches the screen on the third frame after [AppToast.show].
  Future<void> settleToast(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Dismisses everything and lets removal animations plus the deferred
  /// overlay teardown finish, so no timers outlive the test body.
  Future<void> flushToasts(WidgetTester tester) async {
    AppToast.toastification.dismissAll(delayForAnimation: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets("identical toast on screen refreshes instead of stacking", (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    AppToast.init(key: navKey);
    await pumpHost(tester, navKey);

    AppToast.error(title: "Upload failed", holdDuration: 5);
    await settleToast(tester);
    expect(find.text("Upload failed"), findsOneWidget);

    AppToast.error(title: "Upload failed", holdDuration: 5);
    await settleToast(tester);
    expect(find.text("Upload failed"), findsOneWidget);

    // Shake settles without leaving extra copies behind.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Upload failed"), findsOneWidget);

    await flushToasts(tester);
  });

  testWidgets("different messages still stack", (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    AppToast.init(key: navKey);
    await pumpHost(tester, navKey);

    AppToast.error(title: "Upload failed", holdDuration: 5);
    await settleToast(tester);

    AppToast.info(title: "Recovered 2 recordings", holdDuration: 5);
    await settleToast(tester);

    expect(find.text("Upload failed"), findsOneWidget);
    expect(find.text("Recovered 2 recordings"), findsOneWidget);

    await flushToasts(tester);
  });

  testWidgets("a swipe throws the toast off screen", (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    AppToast.init(key: navKey);
    await pumpHost(tester, navKey);

    AppToast.error(title: "Upload failed", holdDuration: 5);
    await settleToast(tester);
    expect(find.text("Upload failed"), findsOneWidget);

    await tester.fling(find.text("Upload failed"), const Offset(0, -120), 800);
    // First frame starts the throw; the rest lets it finish, then the host's
    // deferred removal runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Upload failed"), findsNothing);

    await flushToasts(tester);
  });

  testWidgets("a drag too small to dismiss springs back", (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    AppToast.init(key: navKey);
    await pumpHost(tester, navKey);

    AppToast.error(title: "Upload failed", holdDuration: 5);
    await settleToast(tester);

    final before = tester.getCenter(find.text("Upload failed"));
    final gesture = await tester.startGesture(before);
    await gesture.moveBy(const Offset(0, -30));
    // Hold still before letting go, so this reads as a slow drag rather than
    // a fling — velocity alone would otherwise dismiss it.
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    // Spring settles back to the resting slot; the toast is still on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text("Upload failed"), findsOneWidget);
    expect(
      (tester.getCenter(find.text("Upload failed")) - before).distance,
      lessThan(1),
    );

    await flushToasts(tester);
  });

  testWidgets("same message shows again once the first is gone", (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    AppToast.init(key: navKey);
    await pumpHost(tester, navKey);

    AppToast.error(title: "Upload failed", holdDuration: 1);
    await settleToast(tester);
    expect(find.text("Upload failed"), findsOneWidget);

    // Auto-close fires, removal animation runs out.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Upload failed"), findsNothing);

    AppToast.error(title: "Upload failed", holdDuration: 1);
    await settleToast(tester);
    expect(find.text("Upload failed"), findsOneWidget);

    await flushToasts(tester);
  });
}
