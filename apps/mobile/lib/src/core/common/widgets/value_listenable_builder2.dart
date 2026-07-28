import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";

/// Rebuilds [builder] whenever either [valueListenable] or [valueListenable2]
/// changes. Saves nesting two [ValueListenableBuilder]s when a widget depends
/// on exactly two notifiers (e.g. app state + theme mode).
class ValueListenableBuilder2<A, B> extends StatelessWidget {
  const ValueListenableBuilder2({
    super.key,
    required this.valueListenable,
    required this.valueListenable2,
    required this.builder,
    this.child,
  });

  final ValueListenable<A> valueListenable;
  final ValueListenable<B> valueListenable2;
  final Widget? child;
  final Widget Function(BuildContext context, A value, B value2, Widget? child)
  builder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([valueListenable, valueListenable2]),
      builder: (context, child) {
        return builder(
          context,
          valueListenable.value,
          valueListenable2.value,
          child,
        );
      },
      child: child,
    );
  }
}
