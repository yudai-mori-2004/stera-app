import "package:flutter/material.dart";
import "package:solar_icons/solar_icons.dart";
import "package:stera/src/modules/mcap_preview/helpers/mcap_formatters.dart";
import "package:stera/src/modules/mcap_preview/providers/mcap_topic_player_provider.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";

/// White-on-scrim transport controls for the fullscreen visual player:
/// scrubber, timecodes and prev/play/next. Scrub start/end callbacks let the
/// owning view pause and resume its auto-hide timer.
class McapVisualControls extends StatelessWidget {
  final McapTopicPlayerProvider player;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onStep;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  const McapVisualControls({
    super.key,
    required this.player,
    required this.onTogglePlay,
    required this.onStep,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (!player.hasTimeline) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          "${player.messageCount} message${player.messageCount == 1 ? "" : "s"}",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.neutralWhite.withValues(alpha: 0.7),
            fontSize: AppType.sm,
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: context.colors.neutralWhite,
              inactiveTrackColor: context.colors.neutralWhite.withValues(alpha: 0.24),
              thumbColor: context.colors.neutralWhite,
              overlayColor: context.colors.neutralWhite.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: player.positionFraction,
              onChangeStart: (_) => onScrubStart(),
              onChanged: (v) => player.seekToFraction(v),
              onChangeEnd: (_) => onScrubEnd(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lgPlus),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${formatPlaybackSeconds(player.positionSeconds)} / ${formatPlaybackSeconds(player.durationSeconds)}",
                style: TextStyle(
                  color: context.colors.neutralWhite.withValues(alpha: 0.7),
                  fontSize: AppType.sm,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                "${player.currentIndex + 1} / ${player.messageCount}",
                style: TextStyle(
                  color: context.colors.neutralWhite.withValues(alpha: 0.7),
                  fontSize: AppType.sm,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: "Previous frame",
              icon: Icon(
                Icons.skip_previous,
                color: context.colors.neutralWhite,
              ),
              onPressed: () => onStep(-1),
            ),
            const SizedBox(width: AppSpacing.lg),
            Material(
              color: context.colors.neutralWhite.withValues(alpha: 0.24),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: player.isPlaying ? "Pause" : "Play",
                iconSize: 32,
                icon: Icon(
                  player.isPlaying ? SolarIconsBold.pause : SolarIconsBold.play,
                  color: context.colors.neutralWhite,
                ),
                onPressed: onTogglePlay,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            IconButton(
              tooltip: "Next frame",
              icon: Icon(Icons.skip_next, color: context.colors.neutralWhite),
              onPressed: () => onStep(1),
            ),
          ],
        ),
      ],
    );
  }
}
