import "package:flutter/material.dart";

/// The spring every scrollable in the app snaps and bounces with. Tuned to
/// match the press/entrance springs: light, fairly stiff, settles fast with a
/// touch of bounce.
const SpringDescription kAppScrollSpring = SpringDescription(
  mass: 0.5,
  stiffness: 200,
  damping: 18,
);

/// [PageScrollPhysics] that snaps between pages on [kAppScrollSpring] instead
/// of Flutter's default, so a swipe carries its release velocity through and
/// settles with a small bounce.
class SnappyPagePhysics extends PageScrollPhysics {
  const SnappyPagePhysics({super.parent});

  @override
  SpringDescription get spring => kAppScrollSpring;

  @override
  SnappyPagePhysics applyTo(ScrollPhysics? ancestor) {
    return SnappyPagePhysics(parent: buildParent(ancestor));
  }
}

/// [BouncingScrollPhysics] driving edge bounce-back with [kAppScrollSpring].
///
/// Bouncing (not clamping) is used on both platforms so the spring is felt
/// everywhere rather than only on iOS.
class SpringScrollPhysics extends BouncingScrollPhysics {
  const SpringScrollPhysics({super.parent, super.decelerationRate});

  @override
  SpringDescription get spring => kAppScrollSpring;

  @override
  SpringScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SpringScrollPhysics(
      parent: buildParent(ancestor),
      decelerationRate: decelerationRate,
    );
  }
}

/// Applies [SpringScrollPhysics] to every scrollable under the app, so lists,
/// grids, and scroll views all bounce back on the same spring. Install via
/// [MaterialApp.scrollBehavior].
class SpringScrollBehavior extends MaterialScrollBehavior {
  const SpringScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const SpringScrollPhysics();

  /// Android's default glow indicator is redundant once the edge springs back,
  /// and the two read as competing effects — so overscroll paints nothing and
  /// the bounce carries the feedback on every platform.
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
