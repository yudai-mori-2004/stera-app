import "dart:async";
import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/scheduler.dart";
import "package:stera/src/services/mcap_reader/cdr/ros2_message_decoder.dart";
import "package:stera/src/services/mcap_reader/data/models/mcap_records.dart";
import "package:stera/src/services/mcap_reader/mcap_reader.dart";

/// Playback controller for one MCAP topic: builds the message index, then
/// plays messages back on their recorded timeline (or scrubs/steps through
/// them). Frame loads are latest-wins — if decode falls behind the playhead,
/// intermediate frames are skipped rather than queued.
///
/// Image frames are decoded to [frameImage] at display resolution
/// ([decodeTargetWidth]) with one frame of decode-ahead during playback —
/// full-res 4K decode per frame can't sustain the recorded frame rate. A
/// paused/stepped frame is quietly re-decoded at native resolution so
/// pinch-zoom inspection stays sharp.
class McapTopicPlayerProvider extends ChangeNotifier {
  McapTopicPlayerProvider({required this.reader, required this.topic});

  final McapReader reader;
  final McapTopicInfo topic;

  List<McapMessageRef> _index = const [];

  bool isLoading = true;
  String? error;

  bool isPlaying = false;
  int currentIndex = -1;
  DecodedMcapMessage? current;

  /// Decoded current visual frame (JPEG or depth colormap topics).
  ui.Image? frameImage;

  /// Display-resolution decode target (physical px). Set by the page from
  /// MediaQuery; frames are never upscaled past their native size.
  int decodeTargetWidth = 1440;

  /// Subsampled full-recording trajectory for pose topics (packed xyz / log
  /// times), prefetched in the background so scrubbing shows the camera path.
  Float32List? trailPositions;
  Int64List? trailTimesNs;

  /// The playhead in absolute logTime ns (for splitting the trail into
  /// visited / upcoming portions).
  int get playheadNs => _playheadNs;

  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();
  int _anchorNs = 0;
  int _playheadNs = 0;

  int _requestedIndex = -1;
  bool _loadInFlight = false;
  bool _disposed = false;

  // One-frame decode-ahead used during playback.
  int? _prefetchedIndex;
  DecodedMcapMessage? _prefetchedMessage;
  ui.Image? _prefetchedImage;
  bool _prefetchInFlight = false;

  /// Invalidates in-flight full-res upgrades whenever a newer frame lands.
  int _upgradeToken = 0;

  int get messageCount => _index.length;
  bool get hasTimeline => _index.length > 1;

  int get _startNs => _index.isEmpty ? 0 : _index.first.logTimeNs;
  int get _endNs => _index.isEmpty ? 0 : _index.last.logTimeNs;

  double get durationSeconds =>
      _index.isEmpty ? 0 : (_endNs - _startNs) / 1e9;

  double get positionSeconds =>
      _index.isEmpty ? 0 : (_playheadNs - _startNs) / 1e9;

  double get positionFraction {
    final span = _endNs - _startNs;
    if (span <= 0) return 0;
    return ((_playheadNs - _startNs) / span).clamp(0.0, 1.0);
  }

  Future<void> load() async {
    try {
      _index = await reader.buildTopicIndex(topic.channel.id);
      if (_disposed) return;
      if (_index.isEmpty) {
        error = "No messages on this topic";
      } else {
        _playheadNs = _startNs;
        _requestLoad(0);
        unawaited(_loadTrail());
      }
    } on McapReadException catch (e) {
      error = e.message;
    } catch (e) {
      error = "Failed to index topic: $e";
    }
    isLoading = false;
    if (!_disposed) notifyListeners();
  }

  void togglePlay() => isPlaying ? pause() : play();

  void play() {
    if (_index.length < 2 || isPlaying) return;
    // Replay from the start when the playhead sits at the end.
    if (_playheadNs >= _endNs) _playheadNs = _startNs;
    _anchorNs = _playheadNs;
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    isPlaying = true;
    notifyListeners();
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    if (!isPlaying) return;
    isPlaying = false;
    unawaited(_upgradeCurrentFrame());
    if (!_disposed) notifyListeners();
  }

  void seekToFraction(double fraction) {
    if (_index.isEmpty) return;
    final span = _endNs - _startNs;
    _playheadNs = _startNs + (span * fraction.clamp(0.0, 1.0)).round();
    _anchorNs = _playheadNs;
    _clock.reset();
    _showFrameForPlayhead();
    notifyListeners();
  }

  /// Steps one message backward/forward, pausing playback.
  void step(int delta) {
    if (_index.isEmpty) return;
    pause();
    final target = (currentIndex < 0 ? 0 : currentIndex + delta)
        .clamp(0, _index.length - 1);
    _playheadNs = _index[target].logTimeNs;
    _anchorNs = _playheadNs;
    _clock.reset();
    _requestLoad(target);
    notifyListeners();
  }

  void _tick() {
    _playheadNs = _anchorNs + _clock.elapsedMicroseconds * 1000;
    if (_playheadNs >= _endNs) {
      _playheadNs = _endNs;
      pause();
    }
    _showFrameForPlayhead();
    notifyListeners();
  }

  void _showFrameForPlayhead() {
    final index = _indexAtOrBefore(_playheadNs);
    if (index != currentIndex) _requestLoad(index);
  }

  /// Last message with logTime <= [timeNs] (or 0 when before the first).
  int _indexAtOrBefore(int timeNs) {
    var lo = 0;
    var hi = _index.length - 1;
    var result = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_index[mid].logTimeNs <= timeNs) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  void _requestLoad(int index) {
    _requestedIndex = index;
    if (_loadInFlight) return;
    _loadInFlight = true;
    _drainLoads();
  }

  Future<void> _drainLoads() async {
    try {
      while (!_disposed && _requestedIndex != currentIndex) {
        final index = _requestedIndex;
        DecodedMcapMessage decoded;
        ui.Image? image;
        if (index == _prefetchedIndex && _prefetchedMessage != null) {
          decoded = _prefetchedMessage!;
          image = _prefetchedImage;
          _prefetchedIndex = null;
          _prefetchedMessage = null;
          _prefetchedImage = null;
        } else {
          (decoded, image) = await _loadFrame(index, decodeTargetWidth);
        }
        if (_disposed) {
          image?.dispose();
          return;
        }
        _swapFrame(image);
        current = decoded;
        currentIndex = index;
        _upgradeToken++;
        notifyListeners();
        if (isPlaying) _maybePrefetch(index + 1);
      }
      // Settled while paused (step / scrub end): sharpen the shown frame.
      if (!_disposed && !isPlaying) unawaited(_upgradeCurrentFrame());
    } catch (e) {
      if (!_disposed) {
        error = "Failed to read message: $e";
        notifyListeners();
      }
    } finally {
      _loadInFlight = false;
    }
  }

  /// Reads + decodes one message. [targetWidth] bounds JPEG decode size
  /// (null = native resolution).
  Future<(DecodedMcapMessage, ui.Image?)> _loadFrame(
    int index,
    int? targetWidth,
  ) async {
    final message = await reader.readMessage(_index[index]);
    final decoded = Ros2MessageDecoder.decode(topic.schemaName, message.payload);
    ui.Image? image;
    final jpeg = decoded.jpegBytes;
    if (jpeg != null) {
      image = await _decodeJpeg(jpeg, targetWidth);
    } else {
      final depth = decoded.depth;
      if (depth != null) image = await _renderDepth(depth);
    }
    return (decoded, image);
  }

  static Future<ui.Image> _decodeJpeg(Uint8List bytes, int? targetWidth) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// Decode-ahead: read + decode [index] while the current frame is showing,
  /// so the next tick usually swaps in a ready image. One in flight at most.
  void _maybePrefetch(int index) {
    if (_prefetchInFlight || index >= _index.length) return;
    if (_prefetchedIndex == index) return;
    _prefetchInFlight = true;
    unawaited(() async {
      try {
        final (decoded, image) = await _loadFrame(index, decodeTargetWidth);
        if (_disposed) {
          image?.dispose();
          return;
        }
        _prefetchedImage?.dispose();
        _prefetchedIndex = index;
        _prefetchedMessage = decoded;
        _prefetchedImage = image;
      } catch (_) {
        // Prefetch is best-effort; the drain loop will load it on demand.
      } finally {
        _prefetchInFlight = false;
      }
    }());
  }

  /// Re-decodes the frame on screen at native resolution once playback has
  /// settled, so pausing on a 4K frame allows sharp pinch-zoom. Debounced via
  /// [_upgradeToken] — any newer frame or resumed playback discards it.
  Future<void> _upgradeCurrentFrame() async {
    final jpeg = current?.jpegBytes;
    if (jpeg == null) return;
    final token = ++_upgradeToken;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_disposed || token != _upgradeToken || isPlaying) return;
    try {
      final image = await _decodeJpeg(jpeg, null);
      if (_disposed || token != _upgradeToken || isPlaying) {
        image.dispose();
        return;
      }
      _swapFrame(image);
      notifyListeners();
    } catch (_) {
      // Keep showing the display-resolution frame.
    }
  }

  /// Replaces [frameImage], disposing the old image only after the next
  /// rendered frame — the raster thread may still be painting it.
  void _swapFrame(ui.Image? image) {
    final old = frameImage;
    frameImage = image;
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  static const int _maxTrailSamples = 2000;

  /// For pose topics, reads a subsampled sweep of the whole topic and keeps
  /// the positions as a trajectory trail. Messages are ~100 bytes, so even
  /// the capped 2000 reads finish quickly; failures just leave the trail off.
  Future<void> _loadTrail() async {
    if (topic.schemaName != "geometry_msgs/msg/PoseStamped" ||
        _index.length < 2) {
      return;
    }
    try {
      final step = (_index.length / _maxTrailSamples).ceil().clamp(1, 1 << 30);
      final positions = <double>[];
      final times = <int>[];
      for (var i = 0; i < _index.length; i += step) {
        if (_disposed) return;
        final message = await reader.readMessage(_index[i]);
        final decoded =
            Ros2MessageDecoder.decode(topic.schemaName, message.payload);
        final pose = decoded.scene?.poses.firstOrNull;
        if (pose == null) continue;
        times.add(_index[i].logTimeNs);
        positions.addAll([pose.x, pose.y, pose.z]);
      }
      if (_disposed || times.isEmpty) return;
      trailPositions = Float32List.fromList(positions);
      trailTimesNs = Int64List.fromList(times);
      notifyListeners();
    } catch (_) {
      // Trail is a progressive enhancement — the current pose still renders.
    }
  }

  /// Colorizes a 16UC1 depth frame (near = warm, far = dark), normalizing to
  /// the frame's own non-zero range so both LiDAR scales render usefully.
  static Future<ui.Image> _renderDepth(DecodedDepthFrame depth) {
    var minV = 0xFFFF;
    var maxV = 0;
    for (final v in depth.values) {
      if (v == 0) continue;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final span = maxV > minV ? (maxV - minV) : 1;

    final rgba = Uint8List(depth.width * depth.height * 4);
    for (var i = 0; i < depth.values.length; i++) {
      final v = depth.values[i];
      final o = i * 4;
      if (v == 0) {
        rgba[o + 3] = 0xFF; // invalid depth → black
        continue;
      }
      final t = 1.0 - (v - minV) / span; // near → 1, far → 0
      final (r, g, b) = _heatColor(t);
      rgba[o] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = 0xFF;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      depth.width,
      depth.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Simple blue→cyan→green→yellow→red heat ramp for t in [0, 1].
  static (int, int, int) _heatColor(double t) {
    final stops = [
      (0x20, 0x21, 0x60), // deep blue
      (0x00, 0x8F, 0xC7), // cyan
      (0x22, 0xB0, 0x5A), // green
      (0xF5, 0xC5, 0x18), // yellow
      (0xE0, 0x36, 0x2D), // red
    ];
    final scaled = (t.clamp(0.0, 1.0)) * (stops.length - 1);
    final i = scaled.floor().clamp(0, stops.length - 2);
    final f = scaled - i;
    final a = stops[i];
    final b = stops[i + 1];
    return (
      (a.$1 + (b.$1 - a.$1) * f).round(),
      (a.$2 + (b.$2 - a.$2) * f).round(),
      (a.$3 + (b.$3 - a.$3) * f).round(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    frameImage?.dispose();
    _prefetchedImage?.dispose();
    super.dispose();
  }
}
