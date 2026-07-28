import "package:flutter/material.dart";
import "package:flutter/physics.dart";
import "package:go_router/go_router.dart";
import "package:stera/src/core/common/widgets/spring_scroll_physics.dart";

/// How long the spring is given to settle. [SpringCurve] samples the
/// simulation across this window, so it must match the route's
/// `transitionDuration` for the curve to land at ~1.0 on completion.
const Duration kSpringPageDuration = Duration(milliseconds: 600);

/// A [Curve] backed by a real [SpringSimulation] rather than a bezier, so the
/// motion carries a spring's overshoot-and-settle instead of an eased ramp.
///
/// Maps the curve's normalised `t` (0→1) onto the simulation's real-time
/// window ([kSpringPageDuration]); by the end of that window the spring has
/// settled to ~1.0.
class SpringCurve extends Curve {
  SpringCurve({SpringDescription spring = kAppScrollSpring})
    : _sim = SpringSimulation(spring, 0, 1, 0);

  final SpringSimulation _sim;

  static final double _seconds = kSpringPageDuration.inMilliseconds / 1000;

  @override
  double transformInternal(double t) => _sim.x(t * _seconds);
}

/// A go_router page whose entrance rides a spring: the incoming page settles up
/// to full size with a touch of overshoot while fading in.
///
/// Used for routes that would otherwise use a plain fade. Routes that rely on
/// the platform's default transition are deliberately left alone — Cupertino's
/// builder is what supplies the iOS edge swipe-back gesture.
CustomTransitionPage<T> springPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: kSpringPageDuration,
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Opacity stays on a plain eased curve: the spring overshoots past 1.0
      // and FadeTransition rejects out-of-range opacity.
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: SpringCurve(),
              reverseCurve: Curves.easeIn,
            ),
          ),
          child: child,
        ),
      );
    },
  );
}
