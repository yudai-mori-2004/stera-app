import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/physics.dart";
import "package:flutter/widgets.dart";

/// Motion for [AppToast]: a spring entrance with visible overshoot, and a
/// drag-to-dismiss that follows the finger on both axes and throws the pill
/// out along whichever direction it was flung.
///
/// The pieces live here rather than in `app_toast.dart` so the toast file
/// stays about *what* a toast says and this one about how it moves.

/// Underdamped spring (zeta ~= 0.56) — the pill overshoots its resting
/// position and settles back. Used for the entrance and for a drag that
/// didn't travel far enough to dismiss.
const SpringDescription kToastSpring = SpringDescription(
  mass: 1,
  stiffness: 400,
  damping: 22.4,
);

/// Spring the pill back to centre no slower than this, so a released drag
/// never appears to hang.
const Duration _kEntranceWindow = Duration(milliseconds: 500);

/// Travel of the throw once a swipe has committed to dismissing.
const double _kExitTravel = 160;

/// A drag is a dismissal past either of these — a deliberate short flick
/// counts as much as a slow long drag.
const double _kDismissDistance = 48;
const double _kDismissVelocity = 300;

/// How far the pill can be dragged before it stops following the finger.
const double _kDragBound = 320;

/// Samples [kToastSpring] as a curve, so an [AnimationController]-driven
/// entrance gets spring shape (overshoot included) without leaving the
/// duration-based animation the toast host hands us.
class ToastSpringCurve extends Curve {
  const ToastSpringCurve({this.window = _kEntranceWindow});

  /// Real time the spring is sampled over. Longer than the controller's own
  /// duration would clip the settle; shorter would stretch it.
  final Duration window;

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(kToastSpring, 0, 1, 0);
    return sim.x(t * window.inMilliseconds / Duration.millisecondsPerSecond);
  }
}

/// Entrance/exit transition for a toast pill.
///
/// Enters along the axis it is anchored to — from above for a top toast,
/// from the side for a side-anchored one — springing past its resting spot
/// and back. Leaving is the same path in reverse but eased rather than
/// sprung: an overshoot on the way out reads as a mistake, not as life.
class AppToastTransition extends StatelessWidget {
  const AppToastTransition({
    super.key,
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }

    // Off-screen direction: the edge the toast is anchored to.
    final isCenteredHorizontally = alignment.x == 0;
    final entryAxis = isCenteredHorizontally
        ? Offset(0, alignment.y >= 0 ? 1 : -1)
        : Offset(alignment.x >= 0 ? 1 : -1, 0);

    final curved = CurvedAnimation(
      parent: animation,
      curve: const ToastSpringCurve(),
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) {
        // 1 off-screen, 0 at rest — the same quantity drives every property so
        // slide, fade and scale can't drift apart.
        final away = 1 - curved.value;
        return FractionalTranslation(
          translation: entryAxis * away,
          child: Opacity(
            opacity: (1 - away).clamp(0.0, 1.0),
            child: Transform.scale(scale: 1 - 0.04 * away, child: child),
          ),
        );
      },
    );
  }
}

/// Pan recognizer that claims the gesture arena as soon as the finger has
/// clearly committed to a drag.
///
/// Toasts are laid out inside a scrollable list, whose vertical drag would
/// otherwise take every up/down swipe and leave only sideways ones reaching
/// the pill. Claiming is deferred until past the touch slop so taps on the
/// action button and close icon still land.
class _ToastPanRecognizer extends PanGestureRecognizer {
  _ToastPanRecognizer({super.debugOwner});

  Offset? _origin;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _origin = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final origin = _origin;
    if (event is PointerMoveEvent &&
        origin != null &&
        (event.position - origin).distance > kTouchSlop) {
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }
}

/// Wraps a toast pill in a pan-to-dismiss gesture.
///
/// The pill tracks the finger on both axes. Released short of the threshold
/// it springs home carrying the fling velocity; past it, it keeps going the
/// way it was thrown, fading and shrinking, and calls [onDismissed] once it
/// is gone.
class AppToastDismissible extends StatefulWidget {
  const AppToastDismissible({
    super.key,
    required this.child,
    required this.onDismissed,
  });

  final Widget child;
  final VoidCallback onDismissed;

  @override
  State<AppToastDismissible> createState() => _AppToastDismissibleState();
}

class _AppToastDismissibleState extends State<AppToastDismissible>
    with TickerProviderStateMixin {
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _y = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Direction the pill is thrown once a dismissal commits.
  Offset _exitDirection = Offset.zero;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _exit.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    _x.value = (_x.value + details.delta.dx).clamp(-_kDragBound, _kDragBound);
    _y.value = (_y.value + details.delta.dy).clamp(-_kDragBound, _kDragBound);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dismissing) return;
    final velocity = details.velocity.pixelsPerSecond;
    final offset = Offset(_x.value, _y.value);

    if (offset.distance > _kDismissDistance ||
        velocity.distance > _kDismissVelocity) {
      // Throw it the way it was going: the fling direction if there was one,
      // otherwise wherever the drag had already carried it.
      final heading = velocity.distance > _kDismissVelocity ? velocity : offset;
      _dismissing = true;
      _exitDirection = heading.distance == 0
          ? const Offset(1, 0)
          : heading / heading.distance;
      _exit.forward();
      return;
    }

    _springHome(_x, velocity.dx);
    _springHome(_y, velocity.dy);
  }

  void _springHome(AnimationController controller, double velocity) {
    controller.animateWith(
      SpringSimulation(kToastSpring, controller.value, 0, velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final motion = Listenable.merge([_x, _y, _exit]);
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _ToastPanRecognizer:
            GestureRecognizerFactoryWithHandlers<_ToastPanRecognizer>(
              () => _ToastPanRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..onUpdate = _onPanUpdate
                ..onEnd = _onPanEnd,
            ),
      },
      child: AnimatedBuilder(
        animation: motion,
        child: widget.child,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_exit.value);
          final offset =
              Offset(_x.value, _y.value) + _exitDirection * (_kExitTravel * t);
          return Transform.translate(
            offset: offset,
            child: Opacity(
              opacity: math.max(0, 1 - t),
              child: Transform.scale(scale: 1 - 0.08 * t, child: child),
            ),
          );
        },
      ),
    );
  }
}
