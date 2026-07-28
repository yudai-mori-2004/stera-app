import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/modules/ar_recorder/ui/widgets/ar_coaching_overlay.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:stera_recorder/stera_recorder.dart";

class ArPreviewArea extends StatelessWidget {
  const ArPreviewArea({super.key});

  double _resolvePreviewAspectRatio({
    required int? previewWidth,
    required int? previewHeight,
    required String? recordingResolution,
  }) {
    if (previewWidth != null &&
        previewHeight != null &&
        previewWidth > 0 &&
        previewHeight > 0) {
      return previewWidth / previewHeight;
    }

    final parsedAspectRatio = _tryParseAspectRatio(recordingResolution);
    return parsedAspectRatio ?? (16 / 9);
  }

  double? _tryParseAspectRatio(String? resolution) {
    if (resolution == null) return null;
    final parts = resolution.split("x");
    if (parts.length != 2) return null;

    final width = int.tryParse(parts[0]);
    final height = int.tryParse(parts[1]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }

    return width / height;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.select<ArRecorderProvider, ArRecorderState>(
      (arp) => arp.state,
    );
    final textureId = context.select<ArRecorderProvider, int?>(
      (arp) => arp.textureId,
    );
    final previewWidth = context.select<ArRecorderProvider, int?>(
      (arp) => arp.previewWidth,
    );
    final previewHeight = context.select<ArRecorderProvider, int?>(
      (arp) => arp.previewHeight,
    );
    final recordingResolution = context.select<ArRecorderProvider, String?>(
      (arp) => arp.recordingResolution,
    );

    switch (state) {
      case ArRecorderState.uninitialized:
      case ArRecorderState.initializing:
        return const ArCoachingOverlay();

      case ArRecorderState.ready:
      case ArRecorderState.recording:
      case ArRecorderState.paused:
      case ArRecorderState.cancelling:
      case ArRecorderState.stopping:
        if (textureId != null) {
          final aspectRatio = _resolvePreviewAspectRatio(
            previewWidth: previewWidth,
            previewHeight: previewHeight,
            recordingResolution: recordingResolution,
          );
          // Fill the full device width, cropping top/bottom for display only.
          // The texture buffer stays at the recorded frame's aspect, so the
          // recording keeps its full field of view and correct calibration —
          // the preview just shows a slightly tighter (vertically cropped) view
          // of it. `BoxFit.fitWidth` matches the screen width and lets the
          // height overflow, which the ClipRect trims equally top and bottom.
          return ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.fitWidth,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: aspectRatio,
                  height: 1,
                  child: Texture(textureId: textureId),
                ),
              ),
            ),
          );
        }
        return Center(
          child: Text(
            "Camera preview unavailable",
            style: context.darkTextTheme.bodyLg.copyWith(
              color: context.darkColors.textPrimary,
            ),
          ),
        );

      case ArRecorderState.error:
        return Center(
          child: Icon(
            Icons.error_outline,
            color: context.darkColors.red,
            size: 64,
          ),
        );

      case ArRecorderState.disposed:
        return Center(
          child: Text(
            "Session ended",
            style: context.darkTextTheme.bodyLg.copyWith(
              color: context.darkColors.textPrimary,
            ),
          ),
        );
    }
  }
}
