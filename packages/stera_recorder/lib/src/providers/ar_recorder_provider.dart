import "dart:async";

import "package:flutter/foundation.dart";

import "../config/recorder_permissions.dart";
import "../config/recorder_preferences.dart";
import "../data/enums/ar_recorder_state.dart";
import "../data/enums/ar_tracking_state.dart";
import "../data/models/recording_config.dart";
import "../managers/ar_recording_config_manager.dart";
import "../service/ar_recorder_service.dart";

/// Provider for AR recording state and operations.
///
/// Runtime session state (lifecycle, polling, durations, preview dims) lives
/// here. The recording configuration is owned by [ArRecordingConfigManager];
/// this provider stays the single `ChangeNotifier` the UI binds to and
/// delegates config accessors to the manager so the public API is unchanged.
class ArRecorderProvider extends ChangeNotifier {
  /// Creates a provider driving one AR capture session.
  ///
  /// [preferences] persists the recording settings — pass
  /// [InMemoryRecorderPreferences] to run on the built-in defaults.
  /// [permissions] is only ever *queried*; requesting camera access stays the
  /// host app's responsibility.
  ArRecorderProvider({
    required RecorderPreferences preferences,
    required RecorderPermissions permissions,
  }) : _config = ArRecordingConfigManager(preferences: preferences),
       _permissions = permissions {
    _config.addListener(notifyListeners);
  }

  final ArRecordingConfigManager _config;
  final RecorderPermissions _permissions;
  ArRecorderState _state = ArRecorderState.uninitialized;
  ArRecorderState get state => _state;

  ArTrackingState _trackingState = ArTrackingState.stopped;
  ArTrackingState get trackingState => _trackingState;

  int? _textureId;
  int? get textureId => _textureId;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _outputDirectory;
  String? get outputDirectory => _outputDirectory;

  bool _isLowQualityMode = false;
  bool get isLowQualityMode => _isLowQualityMode;

  String? _lowQualityReason;
  String? get lowQualityReason => _lowQualityReason;

  String? _cameraResolution;
  String? get cameraResolution => _cameraResolution;

  String? _recordingResolution;
  String? get recordingResolution => _recordingResolution;

  int? _previewWidth;
  int? get previewWidth => _previewWidth;

  int? _previewHeight;
  int? get previewHeight => _previewHeight;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  bool get isInitialized =>
      _state == ArRecorderState.ready ||
      _state == ArRecorderState.recording ||
      _state == ArRecorderState.paused ||
      _state == ArRecorderState.cancelling ||
      _state == ArRecorderState.stopping;

  bool get isSessionReady => _state == ArRecorderState.ready;

  Duration _recordingDuration = Duration.zero;
  Duration get recordingDuration => _recordingDuration;

  int? _frameCount;
  int? get frameCount => _frameCount;

  double? _lastDurationSeconds;
  double? get lastDurationSeconds => _lastDurationSeconds;

  int? _lastFramesRecorded;
  int? get lastFramesRecorded => _lastFramesRecorded;

  int? _lastImuSamples;
  int? get lastImuSamples => _lastImuSamples;

  bool _depthSupported = false;
  bool get depthSupported => _depthSupported;

  bool _isFinalizationInProgress = false;
  bool get isFinalizationInProgress => _isFinalizationInProgress;

  // ---------------------------------------------------------------------------
  // Recording configuration — delegated to ArRecordingConfigManager. These thin
  // accessors keep the public API the UI binds to unchanged. Each one reads and
  // writes the identically-named member on [ArRecordingConfigManager], where
  // the sanitization and persistence rules are documented; setting any of them
  // persists the new value and notifies listeners.
  // ---------------------------------------------------------------------------

  /// Whether IMU samples are recorded. See [ArRecordingConfigManager.recordImu].
  bool get recordImu => _config.recordImu;
  set recordImu(bool value) => _config.recordImu = value;

  /// Whether depth maps are recorded.
  bool get recordDepth => _config.recordDepth;
  set recordDepth(bool value) => _config.recordDepth = value;

  /// Whether point clouds are recorded.
  bool get recordPointCloud => _config.recordPointCloud;
  set recordPointCloud(bool value) => _config.recordPointCloud = value;

  /// Whether the reconstructed mesh is recorded.
  bool get recordMesh => _config.recordMesh;
  set recordMesh(bool value) => _config.recordMesh = value;

  /// Whether the RGB video track is recorded.
  bool get recordRgb => _config.recordRgb;
  set recordRgb(bool value) => _config.recordRgb = value;

  /// RGB frame rate in Hz. Out-of-range values snap to a supported rate.
  int get rgbHz => _config.rgbHz;
  set rgbHz(int value) => _config.rgbHz = value;

  /// Depth frame rate in Hz. Out-of-range values snap to a supported rate.
  int get depthHz => _config.depthHz;
  set depthHz(int value) => _config.depthHz = value;

  /// Point cloud rate in Hz. Out-of-range values snap to a supported rate.
  int get pointCloudHz => _config.pointCloudHz;
  set pointCloudHz(int value) => _config.pointCloudHz = value;

  /// IMU sample rate in Hz — one of [RecordingConfig.supportedImuHz].
  int get imuHz => _config.imuHz;
  set imuHz(int value) => _config.imuHz = value;

  /// Whether [rgbHz], [depthHz] and [pointCloudHz] move together.
  bool get syncHz => _config.syncHz;
  set syncHz(bool value) => _config.syncHz = value;

  /// Whether voice commands can start and stop a recording.
  bool get enableVoiceCommands => _config.enableVoiceCommands;
  set enableVoiceCommands(bool value) => _config.enableVoiceCommands = value;

  /// Whether audio cues play on session events.
  bool get enableAudioCues => _config.enableAudioCues;
  set enableAudioCues(bool value) => _config.enableAudioCues = value;

  /// Whether the camera keeps auto-focusing during a take.
  bool get autoFocus => _config.autoFocus;
  set autoFocus(bool value) => _config.autoFocus = value;

  /// Whether exposure stays automatic, rather than locking once it settles.
  bool get autoExposure => _config.autoExposure;
  set autoExposure(bool value) => _config.autoExposure = value;

  /// RGB capture resolution. Changing it clamps [arkitFps] and the spatial
  /// rates into what the new resolution supports.
  RgbVideoResolution get rgbVideoResolution => _config.rgbVideoResolution;
  set rgbVideoResolution(RgbVideoResolution value) =>
      _config.rgbVideoResolution = value;

  /// ARKit session frame rate (iOS only), capped by [rgbVideoResolution].
  int get arkitFps => _config.arkitFps;
  set arkitFps(int value) => _config.arkitFps = value;

  /// Whether inertially-derived channels are recorded alongside raw IMU.
  bool get enableInertialDerived => _config.enableInertialDerived;
  set enableInertialDerived(bool value) =>
      _config.enableInertialDerived = value;

  /// The current settings, assembled into the config handed to the native side.
  RecordingConfig get recordingConfig => _config.recordingConfig;

  /// Reloads every setting from the host's [RecorderPreferences]. Call once
  /// before [initializeSession] so a session starts on the persisted values.
  void loadPersistedToggles() => _config.loadPersistedToggles();

  Timer? _stateUpdateTimer;
  DateTime? _recordingStartTime;
  DateTime? _pausedStartedAt;
  Duration _pausedDuration = Duration.zero;
  bool _isShuttingDownForPageExit = false;
  bool _hasMeaningfulStateChanges(Map<String, dynamic> result) {
    final nextState = _mapNativeState(
      result["state"] as String? ?? "UNINITIALIZED",
    );
    final nextTracking = ArTrackingState.fromString(
      result["trackingState"] as String? ?? "STOPPED",
    );

    return nextState != _state ||
        nextTracking != _trackingState ||
        (result["isRecording"] as bool? ?? false) != _isRecording ||
        (result["isPaused"] as bool? ?? false) != _isPaused ||
        (result["depthSupported"] as bool? ?? false) != _depthSupported ||
        (result["textureId"] as int?) != _textureId ||
        (result["frameCount"] as int?) != _frameCount ||
        (result["isLowQualityMode"] as bool? ?? _isLowQualityMode) !=
            _isLowQualityMode ||
        (result["lowQualityReason"] as String?) != _lowQualityReason ||
        (result["cameraResolution"] as String?) != _cameraResolution ||
        (result["recordingResolution"] as String?) != _recordingResolution ||
        (result["previewWidth"] as int?) != _previewWidth ||
        (result["previewHeight"] as int?) != _previewHeight ||
        (result["error"] as String?) != _errorMessage;
  }

  Never _throwUnknownState(String nativeState) {
    throw StateError("Unknown native AR recorder state: $nativeState");
  }

  void _notifyListenersIfNeeded({bool notify = true}) {
    if (!notify || _isShuttingDownForPageExit) return;
    notifyListeners();
  }

  /// Initializes the AR recording session.
  Future<void> initializeSession({RecordingConfig? configOverride}) async {
    if (_state == ArRecorderState.initializing) return;

    // If retrying from error, clean up previous native session first
    if (_state == ArRecorderState.error) {
      _stateUpdateTimer?.cancel();
      _stateUpdateTimer = null;
      await ArRecorderService.disposeSession();
    }

    debugPrint("📷 ArRecorderProvider: Initializing session...");
    loadPersistedToggles();
    _state = ArRecorderState.initializing;
    _errorMessage = null;
    _isLowQualityMode = false;
    _lowQualityReason = null;
    _cameraResolution = null;
    _recordingResolution = null;
    _previewWidth = null;
    _previewHeight = null;
    notifyListeners();

    try {
      final hasCameraPermission = await _permissions
          .isCameraPermissionGranted();
      if (!hasCameraPermission) {
        _state = ArRecorderState.error;
        _errorMessage =
            "Camera permission is required to record. Please allow camera access.";
        notifyListeners();
        return;
      }

      final initConfig = configOverride ?? recordingConfig;
      final result = await ArRecorderService.initializeSession(
        preferences: {
          "rgbVideoHeight": initConfig.rgbVideoResolution.nominalHeight,
          "autoFocus": initConfig.autoFocus,
          "autoExposure": initConfig.autoExposure,
          "arkitFps": initConfig.arkitFps,
          "enableInertialDerived": initConfig.enableInertialDerived,
        },
      );

      if (result == null) {
        _state = ArRecorderState.error;
        _errorMessage = "Failed to initialize - no response from native";
        notifyListeners();
        return;
      }

      if (result["success"] == true) {
        _textureId = result["textureId"] as int?;
        _depthSupported = result["depthSupported"] as bool? ?? false;
        _previewWidth = result["previewWidth"] as int?;
        _previewHeight = result["previewHeight"] as int?;

        // State might still be initializing on native side
        // We'll poll for ready state
        _startStatePolling();
      } else {
        _state = ArRecorderState.error;
        _errorMessage = result["error"] as String? ?? "Initialization failed";
        debugPrint("❌ ArRecorderProvider: ${result["error"]}");
      }
    } catch (e) {
      _state = ArRecorderState.error;
      _errorMessage = _friendlyErrorMessage(e);
      debugPrint("❌ ArRecorderProvider: Error initializing: $e");
    }

    notifyListeners();
  }

  /// Opens the OS app settings so the user can grant a denied camera
  /// permission, via the host-supplied [RecorderPermissions].
  Future<void> openPermissionSettings() async {
    await _permissions.openSettings();
  }

  /// Starts AR recording.
  Future<void> startRecording({String source = "ui"}) async {
    if (_state != ArRecorderState.ready) {
      debugPrint("⚠️ ArRecorderProvider: Cannot start - not ready");
      return;
    }

    debugPrint("📷 ArRecorderProvider: Starting recording...");

    try {
      final result = await ArRecorderService.startRecording(
        config: recordingConfig,
      );

      if (result == null) {
        _errorMessage = "Failed to start - no response";
        notifyListeners();
        return;
      }

      if (result["success"] == true) {
        _isRecording = true;
        _isPaused = false;
        _state = ArRecorderState.recording;
        _outputDirectory = result["outputDirectory"] as String?;
        _isLowQualityMode = result["isLowQualityMode"] as bool? ?? false;
        _lowQualityReason = result["lowQualityReason"] as String?;
        _cameraResolution = result["cameraResolution"] as String?;
        _recordingResolution = result["recordingResolution"] as String?;
        _previewWidth = result["previewWidth"] as int?;
        _previewHeight = result["previewHeight"] as int?;
        _recordingStartTime = DateTime.now();
        _pausedStartedAt = null;
        _pausedDuration = Duration.zero;
        _recordingDuration = Duration.zero;

        debugPrint("✅ ArRecorderProvider: Recording started");
      } else {
        _errorMessage =
            result["error"] as String? ?? "Failed to start recording";
        debugPrint("❌ ArRecorderProvider: ${result["error"]}");
      }
    } catch (e) {
      _errorMessage = _friendlyErrorMessage(e);
      debugPrint("❌ ArRecorderProvider: Error starting: $e");
    }

    notifyListeners();
  }

  /// Stops AR recording.
  Future<void> stopRecording({String source = "ui"}) async {
    await _stopRecording(notify: true, source: source);
  }

  Future<void> _stopRecording({
    required bool notify,
    required String source,
  }) async {
    if (_state != ArRecorderState.recording &&
        _state != ArRecorderState.paused) {
      debugPrint("⚠️ ArRecorderProvider: Cannot stop - not recording");
      return;
    }

    debugPrint("📷 ArRecorderProvider: Stopping recording...");
    _state = ArRecorderState.stopping;
    _notifyListenersIfNeeded(notify: notify);

    try {
      final result = await ArRecorderService.stopRecording();

      if (result == null) {
        _errorMessage = "Failed to stop - no response";
        _notifyListenersIfNeeded(notify: notify);
        return;
      }

      if (result["success"] == true) {
        _isRecording = false;
        _isPaused = false;
        _state = ArRecorderState.ready;
        _outputDirectory = result["outputDirectory"] as String?;
        _lastDurationSeconds = (result["durationSeconds"] as num?)?.toDouble();
        _lastFramesRecorded = result["framesRecorded"] as int?;
        _lastImuSamples = result["imuSamples"] as int?;
        _isLowQualityMode =
            result["isLowQualityMode"] as bool? ?? _isLowQualityMode;
        _lowQualityReason =
            result["lowQualityReason"] as String? ?? _lowQualityReason;
        _cameraResolution =
            result["cameraResolution"] as String? ?? _cameraResolution;
        _recordingResolution =
            result["recordingResolution"] as String? ?? _recordingResolution;
        _previewWidth = result["previewWidth"] as int? ?? _previewWidth;
        _previewHeight = result["previewHeight"] as int? ?? _previewHeight;
        _recordingStartTime = null;
        _pausedStartedAt = null;
        _pausedDuration = Duration.zero;
        _recordingDuration = Duration.zero;

        debugPrint("✅ ArRecorderProvider: Recording stopped");
      } else {
        _errorMessage =
            result["error"] as String? ?? "Failed to stop recording";
        _state = ArRecorderState.ready;
        _isPaused = false;
        debugPrint("❌ ArRecorderProvider: ${result["error"]}");
      }
    } catch (e) {
      _errorMessage = _friendlyErrorMessage(e);
      _state = ArRecorderState.ready;
      _isPaused = false;
      debugPrint("❌ ArRecorderProvider: Error stopping: $e");
    }

    _notifyListenersIfNeeded(notify: notify);
  }

  /// Pauses an in-progress recording, holding the AR session open. Paused time
  /// is excluded from [recordingDuration].
  Future<void> pauseRecording() async {
    if (_state != ArRecorderState.recording) {
      debugPrint("⚠️ ArRecorderProvider: Cannot pause - not recording");
      return;
    }
    try {
      final result = await ArRecorderService.pauseRecording();
      if (result == null) {
        _errorMessage = "Failed to pause - no response";
        notifyListeners();
        return;
      }
      if (result["success"] == true) {
        _state = ArRecorderState.paused;
        _isPaused = true;
        _pausedStartedAt = DateTime.now();
      } else {
        _errorMessage =
            result["error"] as String? ?? "Failed to pause recording";
      }
    } catch (e) {
      _errorMessage = _friendlyErrorMessage(e);
    }
    notifyListeners();
  }

  /// Resumes a recording paused by [pauseRecording], continuing the same
  /// dataset.
  Future<void> resumeRecording() async {
    if (_state != ArRecorderState.paused) {
      debugPrint("⚠️ ArRecorderProvider: Cannot resume - not paused");
      return;
    }
    try {
      final result = await ArRecorderService.resumeRecording();
      if (result == null) {
        _errorMessage = "Failed to resume - no response";
        notifyListeners();
        return;
      }
      if (result["success"] == true) {
        if (_pausedStartedAt != null) {
          _pausedDuration += DateTime.now().difference(_pausedStartedAt!);
        }
        _pausedStartedAt = null;
        _isPaused = false;
        _state = ArRecorderState.recording;
      } else {
        _errorMessage =
            result["error"] as String? ?? "Failed to resume recording";
      }
    } catch (e) {
      _errorMessage = _friendlyErrorMessage(e);
    }
    notifyListeners();
  }

  /// Aborts the recording and discards its dataset, unlike [stopRecording]
  /// which finalizes it into [outputDirectory].
  Future<void> cancelRecording({String source = "ui"}) async {
    if (_state != ArRecorderState.recording &&
        _state != ArRecorderState.paused) {
      debugPrint("⚠️ ArRecorderProvider: Cannot cancel - not recording");
      return;
    }
    _state = ArRecorderState.cancelling;
    _notifyListenersIfNeeded();
    try {
      final result = await ArRecorderService.cancelRecording();
      if (result == null) {
        _errorMessage = "Failed to cancel - no response";
        _state = ArRecorderState.ready;
        _notifyListenersIfNeeded();
        return;
      }
      if (result["success"] == true) {
        _isRecording = false;
        _isPaused = false;
        _state = ArRecorderState.ready;
        _outputDirectory = null;
        _recordingStartTime = null;
        _pausedStartedAt = null;
        _pausedDuration = Duration.zero;
        _recordingDuration = Duration.zero;
        _frameCount = null;
        _previewWidth = null;
        _previewHeight = null;
      } else {
        _errorMessage =
            result["error"] as String? ?? "Failed to cancel recording";
        _state = ArRecorderState.ready;
      }
    } catch (e) {
      _errorMessage = _friendlyErrorMessage(e);
      _state = ArRecorderState.ready;
    }
    _notifyListenersIfNeeded();
  }

  /// Polls for recording state updates.
  void _startStatePolling() {
    _stateUpdateTimer?.cancel();
    _stateUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      await _updateRecordingState();
    });
  }

  /// Stops polling and fully releases native AR session when leaving page.
  Future<void> shutdownSessionForPageExit() async {
    if (_isShuttingDownForPageExit) return;
    _isShuttingDownForPageExit = true;

    _stateUpdateTimer?.cancel();
    _stateUpdateTimer = null;

    try {
      if (_isRecording ||
          _state == ArRecorderState.recording ||
          _state == ArRecorderState.paused) {
        await _stopRecording(notify: false, source: "page_exit");
      }
      await ArRecorderService.disposeSession();
      _state = ArRecorderState.disposed;
      _isRecording = false;
      _isPaused = false;
      _recordingStartTime = null;
      _pausedStartedAt = null;
      _pausedDuration = Duration.zero;
      _recordingDuration = Duration.zero;
      _frameCount = null;
      _previewWidth = null;
      _previewHeight = null;
    } catch (e) {
      debugPrint("❌ ArRecorderProvider: Error during page-exit shutdown: $e");
    } finally {
      _isShuttingDownForPageExit = false;
    }
  }

  /// Updates recording state from native.
  Future<void> _updateRecordingState() async {
    if (_isShuttingDownForPageExit) return;

    try {
      final result = await ArRecorderService.getRecordingState();

      if (result == null) return;
      if (!_hasMeaningfulStateChanges(result)) {
        if (_isRecording && _recordingStartTime != null) {
          final prevSeconds = _recordingDuration.inSeconds;
          _syncRecordingDuration();
          if (_recordingDuration.inSeconds != prevSeconds) {
            _notifyListenersIfNeeded();
          }
        }
        return;
      }

      final nativeState = result["state"] as String? ?? "UNINITIALIZED";
      final trackingStateStr = result["trackingState"] as String? ?? "STOPPED";

      // Update state mapping
      _state = _mapNativeState(nativeState);
      _trackingState = ArTrackingState.fromString(trackingStateStr);

      final wasPaused = _isPaused;
      final wasRecording = _isRecording;
      _isRecording = result["isRecording"] as bool? ?? false;
      _isPaused =
          result["isPaused"] as bool? ?? (_state == ArRecorderState.paused);
      // Seed the wall-clock anchor when recording starts via a path that
      // didn't go through startRecording() — e.g. a natively-driven
      // armStart fires natively. Without this, the status bar's elapsed
      // counter is stuck at 0s for the whole take.
      if (!wasRecording && _isRecording && _recordingStartTime == null) {
        _recordingStartTime = DateTime.now();
        _recordingDuration = Duration.zero;
        _pausedStartedAt = null;
        _pausedDuration = Duration.zero;
      }
      if (!wasPaused && _isPaused && _pausedStartedAt == null) {
        _pausedStartedAt = DateTime.now();
      }
      if (wasPaused && !_isPaused && _pausedStartedAt != null) {
        _pausedDuration += DateTime.now().difference(_pausedStartedAt!);
        _pausedStartedAt = null;
      }
      _depthSupported = result["depthSupported"] as bool? ?? false;
      _isFinalizationInProgress =
          result["isFinalizationInProgress"] as bool? ?? false;
      _textureId ??= result["textureId"] as int?;
      _frameCount = result["frameCount"] as int?;
      _isLowQualityMode =
          result["isLowQualityMode"] as bool? ?? _isLowQualityMode;
      _lowQualityReason =
          result["lowQualityReason"] as String? ?? _lowQualityReason;
      _cameraResolution =
          result["cameraResolution"] as String? ?? _cameraResolution;
      _recordingResolution =
          result["recordingResolution"] as String? ?? _recordingResolution;
      _previewWidth = result["previewWidth"] as int? ?? _previewWidth;
      _previewHeight = result["previewHeight"] as int? ?? _previewHeight;
      _errorMessage = result["error"] as String? ?? _errorMessage;

      // Update duration if recording
      if (_isRecording && _recordingStartTime != null) {
        _syncRecordingDuration();
      }

      _notifyListenersIfNeeded();
    } catch (e) {
      debugPrint("❌ ArRecorderProvider: Error updating state: $e");
    }
  }

  /// Maps native state string to Dart enum.
  ArRecorderState _mapNativeState(String nativeState) {
    switch (nativeState) {
      case "UNINITIALIZED":
        return ArRecorderState.uninitialized;
      case "INITIALIZING":
        return ArRecorderState.initializing;
      case "READY":
        return ArRecorderState.ready;
      case "RECORDING":
        return ArRecorderState.recording;
      case "PAUSED":
        return ArRecorderState.paused;
      case "CANCELLING":
        return ArRecorderState.cancelling;
      case "STOPPING":
        return ArRecorderState.stopping;
      case "ERROR":
        return ArRecorderState.error;
      case "DISPOSED":
        return ArRecorderState.disposed;
      default:
        _throwUnknownState(nativeState);
    }
  }

  String _friendlyErrorMessage(Object error) {
    if (error is ArRecorderServiceException) {
      return error.message;
    }
    return error.toString();
  }

  void _syncRecordingDuration() {
    final start = _recordingStartTime;
    if (start == null) return;

    final now = DateTime.now();
    final activePaused = _isPaused && _pausedStartedAt != null
        ? now.difference(_pausedStartedAt!)
        : Duration.zero;
    _recordingDuration = now.difference(start) - _pausedDuration - activePaused;
    if (_recordingDuration.isNegative) {
      _recordingDuration = Duration.zero;
    }
  }

  /// Stops polling and releases the provider. Call
  /// [shutdownSessionForPageExit] first to tear the native session down too.
  @override
  void dispose() {
    _stateUpdateTimer?.cancel();
    _config.removeListener(notifyListeners);
    _config.dispose();
    ArRecorderService.disposeSession();
    super.dispose();
  }
}
