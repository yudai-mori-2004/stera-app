import "package:stera/src/modules/demo/constants/app_demo_video.dart";
import "package:flutter/foundation.dart";
import "package:video_player/video_player.dart";

/// Keeps a single initialized network controller for fullscreen demo playback so
/// repeat opens are fast after the first successful load.
class DemoVideoPreloadProvider extends ChangeNotifier {
  VideoPlayerController? _fullscreenController;
  Future<VideoPlayerController>? _obtainInFlight;

  static Uri get _videoUri => Uri.parse(AppDemoVideo.url);

  /// Reserved for API compatibility; network playback does not use the asset bundle.
  Future<void> warmBundle() async {}

  /// Shared controller for fullscreen only. Safe to call from multiple awaiters.
  Future<VideoPlayerController> obtainFullscreenController() async {
    await warmBundle();
    final existing = _fullscreenController;
    if (existing != null && existing.value.isInitialized) {
      return existing;
    }
    if (_obtainInFlight != null) return _obtainInFlight!;
    _obtainInFlight = _createFullscreenController();
    try {
      return await _obtainInFlight!;
    } finally {
      _obtainInFlight = null;
    }
  }

  Future<VideoPlayerController> _createFullscreenController() async {
    final c = VideoPlayerController.networkUrl(_videoUri);
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(1);
      await c.pause();
      await c.seekTo(Duration.zero);
      _fullscreenController = c;
      notifyListeners();
      return c;
    } catch (_) {
      await c.dispose();
      rethrow;
    }
  }

  /// Stops playback when the app backgrounds or is torn down (e.g. debug restart).
  Future<void> pauseFullscreenPlayback() async {
    final c = _fullscreenController;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
      notifyListeners();
    }
  }

  /// Clears the shared fullscreen controller (e.g. after a load error / retry).
  Future<void> resetFullscreenController() async {
    _obtainInFlight = null;
    final old = _fullscreenController;
    _fullscreenController = null;
    await old?.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    final c = _fullscreenController;
    if (c != null) {
      if (c.value.isInitialized) {
        c.pause();
      }
      c.dispose();
    }
    _fullscreenController = null;
    super.dispose();
  }
}
