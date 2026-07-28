import "dart:async";
import "dart:developer" as dev;

import "package:flutter/foundation.dart";
import "package:speech_to_text/speech_recognition_error.dart";
import "package:speech_to_text/speech_recognition_result.dart";
import "package:speech_to_text/speech_to_text.dart";

enum VoiceCommand { startRecording, stopRecording }

/// Listens for voice commands and fires [onCommand] when one is recognised.
///
/// Lifecycle: create -> [init] -> [startListening] -> [dispose].
class VoiceCommandService {
  VoiceCommandService({required this.onCommand});

  final void Function(VoiceCommand) onCommand;

  final SpeechToText _speech = SpeechToText();

  /// Live partial transcript. Cleared after each final recognition result.
  final ValueNotifier<String> transcript = ValueNotifier("");

  /// Whether the service is actively listening.
  final ValueNotifier<bool> isListening = ValueNotifier(false);

  /// Whether the circuit breaker has tripped (disabled for session).
  final ValueNotifier<bool> isDisabled = ValueNotifier(false);

  bool _isInitialized = false;
  bool _shouldListen = false;
  bool _listenInFlight = false;
  bool _isDisposed = false;
  bool _voiceDisabledForSession = false;
  int _consecutiveFailures = 0;
  int _failureCountInWindow = 0;
  DateTime? _failureWindowStart;
  Timer? _restartTimer;

  VoiceCommand? _lastCommand;
  DateTime? _lastCommandTime;

  static const Duration _failureWindow = Duration(seconds: 20);
  static const int _maxFailuresInWindow = 4;
  static const int _maxConsecutiveListenFailures = 3;

  bool get voiceDisabledForSession => _voiceDisabledForSession;

  Future<bool> init() async {
    if (_isDisposed || _voiceDisabledForSession) return false;
    dev.log("VoiceCommandService: Initializing...");
    _isInitialized = false;
    try {
      await _speech.cancel();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    if (!available) {
      dev.log("VoiceCommandService: Speech recognition not available");
      return false;
    }
    // SpeechToText is a singleton — initialize() short-circuits on subsequent
    // calls and never re-registers callbacks. Force-update them so this
    // service instance receives status/error events.
    _speech.errorListener = _onSpeechError;
    _speech.statusListener = _onSpeechStatus;
    _isInitialized = true;
    dev.log("VoiceCommandService: Ready");
    return true;
  }

  void startListening() {
    if (_voiceDisabledForSession || _isDisposed) return;
    _shouldListen = true;
    _scheduleRestart(delay: const Duration(milliseconds: 350));
  }

  Future<void> _attemptStartListening() async {
    if (_isDisposed ||
        _voiceDisabledForSession ||
        !_isInitialized ||
        !_shouldListen) {
      return;
    }
    if (_listenInFlight) return;
    if (_speech.isListening) {
      isListening.value = true;
      return;
    }

    _listenInFlight = true;
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          pauseFor: const Duration(seconds: 8),
        ),
      );
      _consecutiveFailures = 0;
      dev.log("VoiceCommandService: Started listening");
    } catch (e) {
      dev.log("VoiceCommandService: listen() failed - $e");
      _recordFailure();
      if (_voiceDisabledForSession) return;
      _scheduleRestart(delay: const Duration(milliseconds: 1200));
    } finally {
      _listenInFlight = false;
    }
  }

  void stopListening() {
    _shouldListen = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _listenInFlight = false;
    isListening.value = false;
    unawaited(_speech.stop());
    dev.log("VoiceCommandService: Stopped listening");
  }

  void dispose() {
    _isDisposed = true;
    _shouldListen = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    unawaited(_speech.cancel());
    transcript.dispose();
    isListening.dispose();
    isDisabled.dispose();
    dev.log("VoiceCommandService: Disposed");
  }

  void _scheduleRestart({Duration delay = const Duration(milliseconds: 700)}) {
    if (_voiceDisabledForSession || !_shouldListen) return;
    // Cancel any pending restart and schedule a fresh one.
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      if (_isDisposed || _voiceDisabledForSession || !_shouldListen) return;
      unawaited(_attemptStartListening());
    });
  }

  void _recordFailure() {
    final now = DateTime.now();
    if (_failureWindowStart == null ||
        now.difference(_failureWindowStart!) > _failureWindow) {
      _failureWindowStart = now;
      _failureCountInWindow = 0;
      _consecutiveFailures = 0;
    }

    _failureCountInWindow += 1;
    _consecutiveFailures += 1;

    if (_failureCountInWindow >= _maxFailuresInWindow ||
        _consecutiveFailures >= _maxConsecutiveListenFailures) {
      _tripCircuitBreaker();
    }
  }

  void _tripCircuitBreaker() {
    if (_voiceDisabledForSession) return;
    _voiceDisabledForSession = true;
    _shouldListen = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    isListening.value = false;
    isDisabled.value = true;
    unawaited(_speech.cancel());
    dev.log("VoiceCommandService: Circuit breaker tripped");
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (_isDisposed || !_shouldListen || _voiceDisabledForSession) return;

    final text = result.recognizedWords;
    transcript.value = text;

    final cmd = _parseCommand(text);
    if (cmd != null) {
      dev.log("VoiceCommandService: Heard \"$text\" -> ${cmd.name}");
      _fireIfDebounced(cmd);
    }

    if (result.finalResult) transcript.value = "";
  }

  void _onSpeechStatus(String status) {
    if (_isDisposed || _voiceDisabledForSession) return;

    dev.log("VoiceCommandService: Status - $status");
    if (status == "listening") {
      isListening.value = true;
    } else {
      isListening.value = false;
    }
    if (status == "done" || status == "notListening") {
      _scheduleRestart(delay: const Duration(milliseconds: 900));
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (_isDisposed || _voiceDisabledForSession) return;

    dev.log(
      "VoiceCommandService: Error - ${error.errorMsg} (permanent: ${error.permanent})",
    );
    isListening.value = false;

    final msg = error.errorMsg.toLowerCase();
    final isNoMatch = msg == "error_no_match" || msg.contains("no_match");

    if (isNoMatch) {
      // no_match is just silence — not a real failure. Restart immediately.
      _scheduleRestart(delay: const Duration(milliseconds: 500));
      return;
    }

    _recordFailure();
    if (_voiceDisabledForSession) return;

    _scheduleRestart(delay: const Duration(milliseconds: 1400));
  }

  VoiceCommand? _parseCommand(String raw) {
    final text = raw.toLowerCase().trim();
    if (text.contains("start") && text.contains("record")) {
      return VoiceCommand.startRecording;
    }
    if (text.contains("stop") && text.contains("record")) {
      return VoiceCommand.stopRecording;
    }
    return null;
  }

  void _fireIfDebounced(VoiceCommand cmd) {
    final now = DateTime.now();
    if (_lastCommand == cmd &&
        _lastCommandTime != null &&
        now.difference(_lastCommandTime!) < const Duration(seconds: 2)) {
      dev.log("VoiceCommandService: Debounced ${cmd.name}");
      return;
    }
    _lastCommand = cmd;
    _lastCommandTime = now;
    onCommand(cmd);
  }
}
