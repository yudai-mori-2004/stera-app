import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

class ArLowQualityBanner extends StatelessWidget {
  const ArLowQualityBanner({super.key});

  String _buildBannerMessage({
    required String reason,
    required String? recordingResolution,
    required String? cameraResolution,
  }) {
    final resolvedRecording = recordingResolution ?? "unknown";
    final resolvedCamera = cameraResolution ?? "unknown";

    switch (reason) {
      case "camera_resolution_below_target":
        return "Low quality mode: recording at $resolvedRecording because camera resolution is $resolvedCamera and below the target.";
      case "encoder_fallback_resolution":
        return "Low quality mode: recording at fallback resolution $resolvedRecording because the encoder could not use the requested size.";
      case "encoder_fallback_fps":
        return "Low quality mode: using fallback encoder settings at $resolvedRecording because the encoder could not keep the requested frame rate.";
      default:
        return "Low quality mode: using fallback recording settings at $resolvedRecording.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowQualityReason = context.select<ArRecorderProvider, String?>(
      (arp) => arp.lowQualityReason,
    );
    final recordingResolution = context.select<ArRecorderProvider, String?>(
      (arp) => arp.recordingResolution,
    );
    final cameraResolution = context.select<ArRecorderProvider, String?>(
      (arp) => arp.cameraResolution,
    );

    final reason = lowQualityReason ?? "camera_resolution_below_target";
    final yellowColor = context.darkColors.yellow;
    final message = _buildBannerMessage(
      reason: reason,
      recordingResolution: recordingResolution,
      cameraResolution: cameraResolution,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: yellowColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadii.smPlus),
        border: Border.all(color: yellowColor),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: yellowColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.darkTextTheme.bodySm.copyWith(
                color: context.darkColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
