import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";
import "package:stera_recorder/stera_recorder.dart";

/// App-theme colour for a tracking state. Lives here rather than in
/// `stera_recorder` so the package stays free of the app's design system.
extension ArTrackingStateColor on ArTrackingState {
  Color color(BuildContext context) => switch (this) {
    ArTrackingState.tracking => context.darkColors.green,
    ArTrackingState.paused => context.darkColors.yellow,
    ArTrackingState.stopped => context.darkColors.red,
  };
}
