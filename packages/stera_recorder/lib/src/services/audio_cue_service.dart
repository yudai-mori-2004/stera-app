import "dart:async";
import "dart:developer" as dev;

import "package:audioplayers/audioplayers.dart";

/// Plays recording lifecycle sounds using bundled MP3 assets.
///
/// Call [init] once on page open to preload and eliminate first-play latency.
/// Call [dispose] when the page is torn down.
class AudioCueService {
  static AudioPlayer? _startPlayer;
  static AudioPlayer? _stopPlayer;
  static AudioPlayer? _lowBatteryPlayer;
  static AudioPlayer? _warnLowBatteryPlayer;
  static AudioPlayer? _lowStoragePlayer;
  static bool _initialized = false;

  static const Duration _cueTimeout = Duration(seconds: 10);

  // Minimum silence enforced *before* a battery cue plays, measured from the
  // end of the previous cue. Keeps the recording-start stack (start cue ->
  // low-battery warning -> low-battery alert) from running together: each
  // battery announcement is spaced this far behind whatever played last.
  static const Duration _batteryCueGap = Duration(seconds: 10);

  // Serializes cue playback so two cues never sound at once. A cue triggered
  // while another is playing (e.g. the low-battery warning firing the instant
  // recording starts, on top of the start cue) queues behind it instead of
  // overlapping and fighting for the audio session.
  static Future<void> _cueTail = Future<void>.value();

  // Wall-clock time the last cue finished, used to space battery cues. Starts
  // in the distant past so the first battery cue never waits.
  static DateTime _lastCueEndAt = DateTime.fromMillisecondsSinceEpoch(0);

  // The cues ship with this package, so their asset keys carry the
  // `packages/<name>/` prefix Flutter gives package assets. audioplayers
  // otherwise prepends "assets/" to every AssetSource path, so each player gets
  // a cache with an empty prefix and the full key below.
  static const String _soundsDir = "packages/stera_recorder/assets/sounds";
  static final AudioCache _cache = AudioCache(prefix: "");

  static AssetSource get _startSource =>
      AssetSource("$_soundsDir/start_recording_new.mp3");
  static AssetSource get _stopSource =>
      AssetSource("$_soundsDir/stop_recording_new.mp3");
  static AssetSource get _lowBatterySource =>
      AssetSource("$_soundsDir/low_battery.mp3");
  static AssetSource get _warnLowBatterySource =>
      AssetSource("$_soundsDir/warn_about_low_battery.mp3");
  static AssetSource get _lowStorageSource =>
      AssetSource("$_soundsDir/warning_low_storage_new.mp3");

  static AudioPlayer _newPlayer() => AudioPlayer()..audioCache = _cache;

  static Future<void> init() async {
    if (_initialized) return;
    dev.log("AudioCueService: Initializing...");
    try {
      // Pin the plugin's audio-session config so cues survive the other
      // audio-session users on this page (speech-to-text, the AR session).
      // iOS: use the same category STT uses (.playAndRecord) so its
      // start/stop never triggers a category change that re-routes or
      // silences a cue mid-play; .defaultToSpeaker keeps output on the loud
      // speaker instead of the earpiece; .mixWithOthers keeps our activation
      // from interrupting theirs. Android: cues are short UI sounds — take
      // transient may-duck focus instead of full media focus.
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      _startPlayer = _newPlayer();
      _stopPlayer = _newPlayer();
      _lowBatteryPlayer = _newPlayer();
      _warnLowBatteryPlayer = _newPlayer();
      _lowStoragePlayer = _newPlayer();
      await _startPlayer!.setReleaseMode(ReleaseMode.stop);
      await _stopPlayer!.setReleaseMode(ReleaseMode.stop);
      await _lowBatteryPlayer!.setReleaseMode(ReleaseMode.stop);
      await _warnLowBatteryPlayer!.setReleaseMode(ReleaseMode.stop);
      await _lowStoragePlayer!.setReleaseMode(ReleaseMode.stop);
      await _startPlayer!.setSource(_startSource);
      await _stopPlayer!.setSource(_stopSource);
      await _lowBatteryPlayer!.setSource(_lowBatterySource);
      await _warnLowBatteryPlayer!.setSource(_warnLowBatterySource);
      await _lowStoragePlayer!.setSource(_lowStorageSource);
      _initialized = true;
      dev.log("AudioCueService: Ready");
    } catch (e) {
      dev.log("AudioCueService: Failed to initialize - $e");
    }
  }

  /// Plays the start recording cue and waits for it to finish.
  static Future<void> playStartCue() async {
    if (!_initialized || _startPlayer == null) return;
    await _playAndWait(_startPlayer!, _startSource, "start cue");
  }

  /// Plays the stop recording cue and waits for it to finish.
  static Future<void> playStopCue() async {
    if (!_initialized || _stopPlayer == null) return;
    await _playAndWait(_stopPlayer!, _stopSource, "stop cue");
  }

  /// Plays the low-battery alert cue and waits for it to finish. Spaced
  /// [_batteryCueGap] behind the previous cue so it never runs into the start
  /// or warning cue.
  static Future<void> playLowBatteryCue() async {
    if (!_initialized || _lowBatteryPlayer == null) return;
    await _playAndWait(
      _lowBatteryPlayer!,
      _lowBatterySource,
      "low battery cue",
      gapBefore: _batteryCueGap,
    );
  }

  /// Plays the "warn about low battery" cue and waits for it to finish. Spaced
  /// [_batteryCueGap] behind the previous cue (e.g. the start cue) so the two
  /// don't overlap.
  static Future<void> playWarnLowBatteryCue() async {
    if (!_initialized || _warnLowBatteryPlayer == null) return;
    await _playAndWait(
      _warnLowBatteryPlayer!,
      _warnLowBatterySource,
      "warn low battery cue",
      gapBefore: _batteryCueGap,
    );
  }

  /// Plays the low-storage warning cue and waits for it to finish.
  static Future<void> playLowStorageCue() async {
    if (!_initialized || _lowStoragePlayer == null) return;
    await _playAndWait(
      _lowStoragePlayer!,
      _lowStorageSource,
      "low storage cue",
    );
  }

  /// Runs [action] after any in-flight/queued cue completes, keeping playback
  /// strictly sequential. Errors in one cue never break the chain.
  static Future<void> _serialize(Future<void> Function() action) {
    final result = _cueTail.then((_) => action());
    _cueTail = result.catchError((_) {});
    return result;
  }

  static Future<void> _playAndWait(
    AudioPlayer player,
    AssetSource source,
    String cueName, {
    Duration gapBefore = Duration.zero,
  }) => _serialize(() => _playAndWaitInner(player, source, cueName, gapBefore));

  static Future<void> _playAndWaitInner(
    AudioPlayer player,
    AssetSource source,
    String cueName,
    Duration gapBefore,
  ) async {
    // Enforce spacing from the previous cue before this one starts. Runs inside
    // the serialized chain, so the wait holds back only later-queued cues.
    if (gapBefore > Duration.zero) {
      final elapsed = DateTime.now().difference(_lastCueEndAt);
      final remaining = gapBefore - elapsed;
      if (remaining > Duration.zero) {
        dev.log(
          "AudioCueService: spacing $cueName by ${remaining.inMilliseconds}ms",
        );
        await Future.delayed(remaining);
      }
    }
    dev.log("AudioCueService: Playing $cueName");
    StreamSubscription<void>? sub;
    try {
      await player.stop();
      final completer = Completer<void>();
      sub = player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
      await player.play(source);
      await completer.future.timeout(
        _cueTimeout,
        onTimeout: () {
          dev.log("AudioCueService: $cueName timed out");
        },
      );
      dev.log("AudioCueService: $cueName finished");
    } catch (e) {
      dev.log("AudioCueService: $cueName failed - $e");
    } finally {
      await sub?.cancel();
      // Mark completion so the next battery cue can measure its gap from here.
      _lastCueEndAt = DateTime.now();
    }
  }

  static Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    try {
      await _startPlayer?.dispose();
      await _stopPlayer?.dispose();
      await _lowBatteryPlayer?.dispose();
      await _warnLowBatteryPlayer?.dispose();
      await _lowStoragePlayer?.dispose();
    } catch (_) {}
    _startPlayer = null;
    _stopPlayer = null;
    _lowBatteryPlayer = null;
    _warnLowBatteryPlayer = null;
    _lowStoragePlayer = null;
    dev.log("AudioCueService: Disposed");
  }
}
