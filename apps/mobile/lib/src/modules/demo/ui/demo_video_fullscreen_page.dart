import "dart:async";

import "package:stera/src/modules/demo/providers/demo_video_preload_provider.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:stera/src/core/theme/app_type.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:solar_icons/solar_icons.dart";
import "package:video_player/video_player.dart";

/// Fullscreen demo playback (landscape-friendly).
class DemoVideoFullscreenPage extends StatefulWidget {
  const DemoVideoFullscreenPage({super.key});

  static const routeName = "/demo-video";

  @override
  State<DemoVideoFullscreenPage> createState() =>
      _DemoVideoFullscreenPageState();
}

class _DemoVideoFullscreenPageState extends State<DemoVideoFullscreenPage>
    with WidgetsBindingObserver {
  static const Duration _autoHideControlsAfter = Duration(seconds: 10);

  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;
  bool _isScrubbing = false;
  double? _scrubMs;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  bool _resumePlaybackAfterForeground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachController());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop playback when the app leaves the foreground (so audio doesn't keep
    // running behind the lock screen) and resume it on return.
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (c.value.isPlaying) {
          _resumePlaybackAfterForeground = true;
          c.pause();
          if (mounted) setState(() {});
        }
        return;
      case AppLifecycleState.resumed:
        if (_resumePlaybackAfterForeground) {
          _resumePlaybackAfterForeground = false;
          c.play();
          if (mounted) setState(() {});
        }
        return;
    }
  }

  Future<void> _attachController() async {
    if (!mounted) return;
    final preload = context.read<DemoVideoPreloadProvider>();
    try {
      final controller = await preload.obtainFullscreenController();
      if (!mounted) return;
      controller.removeListener(_onTick);
      controller.addListener(_onTick);
      await controller.seekTo(Duration.zero);
      await controller.play();
      setState(() {
        _controller = controller;
        _initialized = true;
        _error = null;
      });
      _scheduleAutoHideControls();
    } catch (_) {
      if (mounted) setState(() => _error = "Could not load video");
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _cancelAutoHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = null;
  }

  void _scheduleAutoHideControls() {
    _cancelAutoHideControls();
    if (!_controlsVisible) return;
    _hideControlsTimer = Timer(_autoHideControlsAfter, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
      _hideControlsTimer = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAutoHideControls();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      c.pause();
      c.seekTo(Duration.zero);
    }
    super.dispose();
  }

  Future<void> _retry() async {
    _cancelAutoHideControls();
    _controller?.removeListener(_onTick);
    setState(() {
      _controller = null;
      _initialized = false;
      _error = null;
    });
    if (!mounted) return;
    await context.read<DemoVideoPreloadProvider>().resetFullscreenController();
    if (!mounted) return;
    await _attachController();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
    _scheduleAutoHideControls();
  }

  static String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 86400);
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return "$m:${s.toString().padLeft(2, "0")}";
  }

  Widget _buildScrubber(VideoPlayerController c) {
    final v = c.value;
    final duration = v.duration;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final positionMs = v.position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();
    final sliderValue = _isScrubbing && _scrubMs != null
        ? _scrubMs!.clamp(0, maxMs)
        : positionMs;

    final displayPosition = Duration(
      milliseconds: sliderValue.round().clamp(0, duration.inMilliseconds),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.none, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
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
              value: sliderValue.clamp(0, maxMs).toDouble(),
              max: maxMs,
              onChangeStart: duration.inMilliseconds > 0
                  ? (_) {
                      _cancelAutoHideControls();
                      setState(() {
                        _isScrubbing = true;
                      });
                    }
                  : null,
              onChanged: duration.inMilliseconds > 0
                  ? (ms) {
                      setState(() {
                        _scrubMs = ms;
                      });
                    }
                  : null,
              onChangeEnd: duration.inMilliseconds > 0
                  ? (ms) async {
                      await c.seekTo(Duration(milliseconds: ms.round()));
                      if (mounted) {
                        setState(() {
                          _isScrubbing = false;
                          _scrubMs = null;
                        });
                        _scheduleAutoHideControls();
                      }
                    }
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(displayPosition),
                  style: TextStyle(
                    color: context.colors.neutralWhite.withValues(alpha: 0.7),
                    fontSize: AppType.sm,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: context.colors.neutralWhite.withValues(alpha: 0.7),
                    fontSize: AppType.sm,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.neutralBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_error != null)
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.neutralWhite.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        onPressed: _retry,
                        child: const Text("Retry"),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (!_initialized || _controller == null)
            Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.neutralWhite,
                ),
              ),
            )
          else
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        setState(() => _controlsVisible = !_controlsVisible);
                        if (_controlsVisible) {
                          _scheduleAutoHideControls();
                        } else {
                          _cancelAutoHideControls();
                        }
                      },
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: Stack(
                  children: [
                    Positioned(
                      top: 4,
                      left: 4,
                      child: IconButton(
                        tooltip: "Close",
                        icon: Icon(
                          Icons.close,
                          color: context.colors.neutralWhite,
                        ),
                        onPressed: () {
                          _cancelAutoHideControls();
                          context.pop();
                        },
                      ),
                    ),
                    if (_initialized && _controller != null && _error == null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 8,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildScrubber(_controller!),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Material(
                                  color: context.colors.neutralWhite.withValues(alpha: 0.24),
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: IconButton(
                                    tooltip: _controller!.value.isPlaying
                                        ? "Pause"
                                        : "Play",
                                    iconSize: 32,
                                    icon: Icon(
                                      _controller!.value.isPlaying
                                          ? SolarIconsBold.pause
                                          : SolarIconsBold.play,
                                      color: context.colors.neutralWhite,
                                    ),
                                    onPressed: _togglePlay,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
