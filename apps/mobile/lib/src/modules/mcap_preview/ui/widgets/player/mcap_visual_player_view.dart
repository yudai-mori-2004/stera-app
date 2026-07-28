import "dart:async";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/modules/mcap_preview/providers/mcap_topic_player_provider.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_error_state.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/mcap_loading_state.dart";
import "package:stera/src/modules/mcap_preview/ui/widgets/player/mcap_visual_controls.dart";
import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";

/// Fullscreen immersive player for image/depth topics (styled like
/// `DemoVideoFullscreenPage`): tap toggles the auto-hiding controls, pinch
/// zooms the frame. Owns controls visibility; playback state lives in the
/// borrowed [McapTopicPlayerProvider].
class McapVisualPlayerView extends StatefulWidget {
  final McapTopicPlayerProvider player;
  final McapTopicInfo topic;

  const McapVisualPlayerView({
    super.key,
    required this.player,
    required this.topic,
  });

  @override
  State<McapVisualPlayerView> createState() => _McapVisualPlayerViewState();
}

class _McapVisualPlayerViewState extends State<McapVisualPlayerView> {
  static const Duration _autoHideControlsAfter = Duration(seconds: 3);

  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  bool _wasPlaying = false;

  McapTopicPlayerProvider get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  /// Re-shows the controls whenever playback stops (end of topic, pause).
  void _onPlayerChanged() {
    if (_wasPlaying && !_player.isPlaying) _showControls();
    _wasPlaying = _player.isPlaying;
  }

  void _showControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = null;
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_player.isPlaying) return;
    _hideControlsTimer = Timer(_autoHideControlsAfter, () {
      _hideControlsTimer = null;
      if (mounted && _player.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      setState(() => _controlsVisible = true);
      _scheduleHideControls();
    }
  }

  void _togglePlay() {
    _player.togglePlay();
    if (_player.isPlaying) {
      _scheduleHideControls();
    } else {
      _showControls();
    }
  }

  void _step(int delta) {
    _player.step(delta); // pauses playback
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: context.w,
        height: context.h,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage(AppAssets.texture),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              context.colors.surfacePrimary,
              BlendMode.modulate,
            ),
          ),
        ),
        child: ListenableBuilder(
          listenable: _player,
          builder: (context, _) {
            if (_player.isLoading) {
              return const McapLoadingState(message: "Decoding frames…");
            }
            final error = _player.error;
            if (error != null && _player.current == null) {
              return SafeArea(
                child: Stack(
                  children: [
                    const _CloseButton(),
                    McapErrorState(message: error, showIcon: false),
                  ],
                ),
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: Center(
                      child: InteractiveViewer(
                        maxScale: 8,
                        child: _FrameView(image: _player.frameImage),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Scrims keep the white controls readable whatever is
                        // behind them (bright frames, light texture). Outside
                        // SafeArea so they bleed to the physical screen edges
                        // like a standard video player.
                        const _EdgeScrim(top: true),
                        const _EdgeScrim(top: false),
                        SafeArea(
                          child: Stack(
                            children: [
                              const _CloseButton(),
                              Positioned(
                                top: 12,
                                left: 56,
                                right: 16,
                                child: Text(
                                  widget.topic.topic,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.bodySmMedium
                                      .copyWith(color: context.colors.neutralWhite),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 8,
                                child: McapVisualControls(
                                  player: _player,
                                  onTogglePlay: _togglePlay,
                                  onStep: _step,
                                  onScrubStart: () =>
                                      _hideControlsTimer?.cancel(),
                                  onScrubEnd: _scheduleHideControls,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EdgeScrim extends StatelessWidget {
  final bool top;

  const _EdgeScrim({required this.top});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: top ? 96 : 160,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [context.colors.neutralBlack.withValues(alpha: 0.55), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      child: IconButton(
        tooltip: "Close",
        style: IconButton.styleFrom(
          // Self-contained contrast: this button also renders over the bare
          // texture (error state), where no scrim backs it.
          backgroundColor: context.colors.neutralBlack.withValues(alpha: 0.35),
          foregroundColor: context.colors.neutralWhite,
        ),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _FrameView extends StatelessWidget {
  final ui.Image? image;

  const _FrameView({required this.image});

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) return const SizedBox.shrink();
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: width,
        height: height,
        child: RawImage(image: image, width: width, height: height),
      ),
    );
  }
}
