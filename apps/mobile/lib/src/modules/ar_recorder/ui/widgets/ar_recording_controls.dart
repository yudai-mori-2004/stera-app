
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/common/widgets/pressable.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

/// Bottom AR controls: compact circular ring + label (same language as the original
/// design, smaller than the original 72px controls).
class ArRecordingControls extends StatelessWidget {
  final VoidCallback onStartPressed;
  final VoidCallback onStopPressed;

  const ArRecordingControls({
    super.key,
    required this.onStartPressed,
    required this.onStopPressed,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.select<ArRecorderProvider, ArRecorderState>(
      (arp) => arp.state,
    );
    final isRecording = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isRecording,
    );
    final isSessionReady = context.select<ArRecorderProvider, bool>(
      (arp) => arp.isSessionReady,
    );

    final accent = context.darkColors.red;

    Widget centered(Widget child) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: child,
        ),
      );
    }

    if (state == ArRecorderState.stopping) {
      return centered(const _ArSavingControl());
    }

    if (isRecording) {
      return centered(
        _ArCircleControl(
          icon: Icons.stop_rounded,
          label: "Stop & Save",
          accentColor: accent,
          onTap: () {
            HapticFeedback.heavyImpact();
            onStopPressed();
          },
        ),
      );
    }

    if (isSessionReady) {
      return centered(
        _ArCircleControl(
          icon: Icons.videocam_rounded,
          label: "Start Recording",
          accentColor: accent,
          onTap: () {
            HapticFeedback.mediumImpact();
            onStartPressed();
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ArCircleControl extends StatelessWidget {
  const _ArCircleControl({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  static const double _diameter = 56;
  static const double _borderWidth = 3;
  static const double _iconSize = 28;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _diameter,
            height: _diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accentColor, width: _borderWidth),
              color: accentColor.withValues(alpha: 0.2),
            ),
            child: Icon(icon, color: accentColor, size: _iconSize),
          ),
          const SizedBox(height: AppSpacing.xsPlus),
          Text(
            label,
            style: context.darkTextTheme.headSm.copyWith(
              color: context.darkColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArSavingControl extends StatelessWidget {
  const _ArSavingControl();

  static const double _box = 56;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _box,
          height: _box,
          child: CircularProgressIndicator(
            color: context.darkColors.textPrimary,
            strokeWidth: 2.5,
          ),
        ),
        const SizedBox(height: AppSpacing.xsPlus),
        Text(
          "Saving...",
          style: context.darkTextTheme.headSm.copyWith(
            color: context.darkColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
