import "dart:ui" show ImageFilter;

import "package:stera/src/core/constants/app_assets.dart";
import "package:stera/src/core/router/demo_inline_video_route_observer.dart";
import "package:stera/src/modules/demo/constants/app_demo_video.dart";
import "package:stera/src/core/theme/app_radii.dart";
import "package:stera/src/core/common/utils/extensions.dart";
import "package:stera/src/core/theme/app_spacing.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:solar_icons/solar_icons.dart";
import "package:video_player/video_player.dart";

/// Rec. 709 luma weights; [saturation] 1.0 = unchanged, >1 richer chroma.
List<double> _saturationColorMatrix(double saturation) {
  final inv = 1.0 - saturation;
  final r = inv * 0.2126;
  final g = inv * 0.7152;
  final b = inv * 0.0722;
  return <double>[
    r + saturation,
    g,
    b,
    0,
    0,
    r,
    g + saturation,
    b,
    0,
    0,
    r,
    g,
    b + saturation,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// In-card network playback for onboarding; uses a dedicated controller so
/// fullscreen can keep using [DemoVideoPreloadProvider] without attaching two
/// [VideoPlayer] widgets to one controller.
class DemoVideoInlinePreview extends StatefulWidget {
  const DemoVideoInlinePreview({
    super.key,
    required this.onOpenFullscreen,
    this.aspectRatio = 3.1 / 2,
    this.outerClipRadius = 24,
    this.autoplayOnInit = true,
    this.onPlayingBegan,
    this.onFirstUserInteraction,
  });

  final Future<void> Function() onOpenFullscreen;
  final double aspectRatio;
  final double outerClipRadius;
  final bool autoplayOnInit;
  final VoidCallback? onPlayingBegan;
  final VoidCallback? onFirstUserInteraction;

  @override
  State<DemoVideoInlinePreview> createState() => _DemoVideoInlinePreviewState();
}

class _DemoVideoInlinePreviewState extends State<DemoVideoInlinePreview>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _error;
  late final AnimationController _gradientController;
  late final AnimationController _playIconController;
  bool _resumePlaybackAfterForeground = false;
  bool _listenerWasPlaying = false;
  bool _firstUserInteractionReported = false;
  PageRoute<dynamic>? _subscribedRoute;
  bool _pendingProgressRebuild = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _playIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _init();
  }

  void _subscribeRouteAware() {
    final route = ModalRoute.of(context);
    if (route is! PageRoute) return;
    if (identical(route, _subscribedRoute)) return;
    demoInlineVideoRouteObserver.unsubscribe(this);
    _subscribedRoute = route;
    demoInlineVideoRouteObserver.subscribe(this, route);
  }

  void _pauseIfPlaying({required bool rebuildUi}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    c.pause();
    if (!rebuildUi || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeRouteAware();
    // Light mode uses a static glow; dark mode breathes.
    final light = Theme.of(context).brightness == Brightness.light;
    if (light) {
      _gradientController.stop();
    } else if (!_gradientController.isAnimating) {
      _gradientController.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (c != null && c.value.isInitialized && c.value.isPlaying) {
          _resumePlaybackAfterForeground = true;
          c.pause();
          if (mounted) setState(() {});
        }
        return;
      case AppLifecycleState.resumed:
        if (_resumePlaybackAfterForeground &&
            mounted &&
            _controller != null &&
            _controller!.value.isInitialized) {
          _resumePlaybackAfterForeground = false;
          _controller!.play();
          setState(() {});
        }
        return;
    }
  }

  void _onVideoValueChangedForPlayingBegan() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final now = c.value.isPlaying;
    if (!_listenerWasPlaying && now) {
      widget.onPlayingBegan?.call();
    }
    _listenerWasPlaying = now;
  }

  void _reportFirstUserInteraction() {
    if (_firstUserInteractionReported) return;
    _firstUserInteractionReported = true;
    widget.onFirstUserInteraction?.call();
  }

  void _onVideoProgressChanged() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_pendingProgressRebuild) return;
      _pendingProgressRebuild = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingProgressRebuild = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(AppDemoVideo.url));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(true);
      await c.setVolume(1);
      if (widget.autoplayOnInit) {
        await c.play();
      } else {
        await c.pause();
      }
      _listenerWasPlaying = c.value.isPlaying;
      _playIconController.value = c.value.isPlaying ? 0.0 : 1.0;
      c.addListener(_onVideoValueChangedForPlayingBegan);
      c.addListener(_onVideoProgressChanged);
      setState(() {
        _controller = c;
        _ready = true;
        _error = null;
      });
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = "Could not load video");
    }
  }

  Future<void> _retry() async {
    final old = _controller;
    setState(() {
      _error = null;
      _ready = false;
      _controller = null;
    });
    if (old != null) {
      old.removeListener(_onVideoValueChangedForPlayingBegan);
      old.removeListener(_onVideoProgressChanged);
      if (old.value.isInitialized) {
        await old.pause();
      }
      await old.dispose();
    }
    await _init();
  }

  Future<void> _togglePlayPause() async {
    _reportFirstUserInteraction();
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
      _playIconController.forward();
    } else {
      await c.play();
      _playIconController.reverse();
    }
    if (mounted) setState(() {});
  }

  Future<void> _handleFullscreen() async {
    _reportFirstUserInteraction();
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.pause();
    _playIconController.forward();
    if (mounted) setState(() {});
    try {
      await widget.onOpenFullscreen();
    } finally {
      if (mounted && _controller != null && _controller!.value.isInitialized) {
        await _controller!.play();
        _playIconController.reverse();
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void deactivate() {
    _pauseIfPlaying(rebuildUi: false);
    super.deactivate();
  }

  @override
  void didPushNext() {
    _pauseIfPlaying(rebuildUi: true);
  }

  @override
  void dispose() {
    demoInlineVideoRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _gradientController.dispose();
    _playIconController.dispose();
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onVideoValueChangedForPlayingBegan);
      c.removeListener(_onVideoProgressChanged);
      if (c.value.isInitialized) {
        c.pause();
      }
      c.dispose();
    }
    super.dispose();
  }

  Widget _heroLightModeGlow() {
    return Transform.scale(
      scale: 1.035,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturationColorMatrix(1.72)),
          child: Opacity(
            opacity: 0.76,
            child: Image.asset(
              AppAssets.appVidDemoThumbnail,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }

  static final List<double> _heroLightVideoColorMatrix = _saturationColorMatrix(
    1.26,
  );

  Widget _heroDarkModeBackdrop() {
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_gradientController.value);
        final glowOpacity = (0.26 + 0.3 * t).clamp(0.0, 1.0);
        return Transform.scale(
          scale: 1.05 + 0.04 * t,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 34 + 8 * t,
              sigmaY: 34 + 8 * t,
            ),
            child: Opacity(
              opacity: glowOpacity,
              child: Image.asset(
                AppAssets.appVidDemoThumbnail,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.outerClipRadius;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          if (isLight) _heroLightModeGlow() else _heroDarkModeBackdrop(),
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(r),
            child: _buildStage(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    // Video unavailable (offline, bad URL, decode failure): fall back to the
    // still thumbnail rather than an error panel, so the card keeps its shape
    // and the section still reads as intended. Tapping retries silently — no
    // error chrome, so a transient network blip self-heals without the user
    // ever being told something broke.
    if (_error != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _retry,
        child: Image.asset(
          AppAssets.appVidDemoThumbnail,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    if (!_ready || _controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(AppAssets.appVidDemoThumbnail, fit: BoxFit.cover),
          const Center(child: CupertinoActivityIndicator()),
        ],
      );
    }

    final c = _controller!;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final videoStack = Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: isLight
                ? ColorFiltered(
                    colorFilter: ColorFilter.matrix(_heroLightVideoColorMatrix),
                    child: VideoPlayer(c),
                  )
                : VideoPlayer(c),
          ),
        ),
        if (isLight) ...[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    context.colors.neutralBlack.withValues(alpha: 0.20),
                  ],
                  stops: const [0.5, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-1.1, -1),
                  end: const Alignment(1.05, 1.05),
                  colors: [
                    context.colors.neutralWhite.withValues(alpha: 0.18),
                    Colors.transparent,
                    context.colors.neutralBlack.withValues(alpha: 0.07),
                  ],
                  stops: const [0, 0.48, 1],
                ),
              ),
            ),
          ),
        ],
        if (!isLight) ...[
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _gradientController,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_gradientController.value);
                final stopLow = 0.34 + 0.2 * t;
                final bottomAlpha = (0.42 + 0.14 * t).clamp(0.0, 0.92);
                final endY = 0.92 + 0.12 * t;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0, -0.85 + 0.12 * t),
                      end: Alignment(0, endY),
                      colors: [
                        Colors.transparent,
                        context.colors.neutralBlack.withValues(alpha: bottomAlpha),
                      ],
                      stops: [stopLow, 1],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _gradientController,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_gradientController.value);
                final a = 0.03 + 0.04 * t;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.2 + 0.5 * t, -1),
                      end: Alignment(1.1 - 0.4 * t, 1.2),
                      colors: [
                        context.colors.neutralWhite.withValues(alpha: a),
                        Colors.transparent,
                        context.colors.neutralBlack.withValues(alpha: 0.14 * t),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        // Animated play icon overlay — fades in on pause, out on play.
        Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _playIconController,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(
                  parent: _playIconController,
                  curve: Curves.easeOutBack,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.colors.neutralBlack.withValues(alpha: isLight ? 0.36 : 0.30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  SolarIconsBold.play,
                  size: 22,
                  color: context.colors.neutralWhite,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayPause,
      child: videoStack,
    );

    // Progress fraction for the thin bar.
    final duration = c.value.duration;
    final position = c.value.position;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        body,
        // Frosted-glass fullscreen button.
        Positioned(
          top: 8,
          right: 8,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.neutralBlack.withValues(alpha: isLight ? 0.28 : 0.32),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _handleFullscreen,
                  tooltip: "Full screen",
                  padding: const EdgeInsets.all(AppSpacing.smPlus),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  style: IconButton.styleFrom(
                    foregroundColor: context.colors.neutralWhite,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(SolarIconsOutline.fullScreen, size: 22),
                ),
              ),
            ),
          ),
        ),
        // Thin progress bar at the bottom edge.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 3,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Track.
                  Positioned.fill(
                    child: ColoredBox(
                      color: context.colors.neutralWhite.withValues(alpha: 0.15),
                    ),
                  ),
                  // Fill.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: constraints.maxWidth * progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colors.neutralWhite.withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(AppRadii.hairline),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
