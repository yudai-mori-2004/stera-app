import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:go_router/go_router.dart";
import "package:stera/src/core/common/widgets/app_header.dart";

void main() {
  Widget hostAt(String location) {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: "/home",
          builder: (_, _) => const Scaffold(
            appBar: AppHeader(text1: "Stera", text2: ""),
            body: SizedBox.shrink(),
          ),
          routes: [
            GoRoute(
              path: "profile",
              builder: (_, _) => const Scaffold(
                appBar: AppHeader(text1: "Profile", text2: ""),
                body: SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets("title holds its place while a bottom sheet is open", (
    tester,
  ) async {
    await tester.pumpWidget(hostAt("/home/profile"));
    await tester.pumpAndSettle();

    final before = tester.getTopLeft(find.text("Profile"));

    final context = tester.element(find.text("Profile"));
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 200),
    );
    await tester.pumpAndSettle();

    expect(find.text("Profile"), findsOneWidget);
    expect(tester.getTopLeft(find.text("Profile")), before);
  });

  testWidgets("a page with no back stack keeps the default title inset", (
    tester,
  ) async {
    await tester.pumpWidget(hostAt("/home"));
    await tester.pumpAndSettle();

    // No back button, so the title starts at the default inset rather than
    // flush against the leading edge.
    expect(tester.getTopLeft(find.text("Stera")).dx, 16);
  });
}
