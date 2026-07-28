import "package:flutter/material.dart";
import "package:solar_icons/solar_icons.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/modules/mcap_preview/helpers/mcap_formatters.dart";
import "package:stera/src/modules/mcap_preview/providers/mcap_topic_player_provider.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_card.dart";

/// Themed transport card for the data-topic player: scrubber, timecodes and
/// prev/play/next. Unlike the visual player these controls never auto-hide,
/// so they drive the [player] directly.
class McapDataControls extends StatelessWidget {
  final McapTopicPlayerProvider player;

  const McapDataControls({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    if (!player.hasTimeline) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Text(
          "${player.messageCount} message${player.messageCount == 1 ? "" : "s"}",
          style: context.textTheme.bodyXs.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: McapCard(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: context.colors.textPrimary,
                  inactiveTrackColor: context.colors.neutralLightGray,
                  thumbColor: context.colors.textPrimary,
                  overlayColor: context.colors.textPrimary.withValues(
                    alpha: 0.1,
                  ),
                ),
                child: Slider(
                  value: player.positionFraction,
                  onChanged: (v) => player.seekToFraction(v),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${formatPlaybackSeconds(player.positionSeconds)} / ${formatPlaybackSeconds(player.durationSeconds)}",
                    style: context.textTheme.bodyXsMono.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  Text(
                    "${player.currentIndex + 1} / ${player.messageCount}",
                    style: context.textTheme.bodyXsMono.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: "Previous message",
                    icon: Icon(
                      Icons.skip_previous,
                      color: context.colors.textPrimary,
                    ),
                    onPressed: () => player.step(-1),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Material(
                    color: context.colors.textPrimary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: player.isPlaying ? "Pause" : "Play",
                      iconSize: 28,
                      icon: Icon(
                        player.isPlaying
                            ? SolarIconsBold.pause
                            : SolarIconsBold.play,
                        color: context.colors.surfacePrimary,
                      ),
                      onPressed: () => player.togglePlay(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  IconButton(
                    tooltip: "Next message",
                    icon: Icon(
                      Icons.skip_next,
                      color: context.colors.textPrimary,
                    ),
                    onPressed: () => player.step(1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
