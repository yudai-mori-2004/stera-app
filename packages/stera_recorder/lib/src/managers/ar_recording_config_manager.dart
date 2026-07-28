import "package:flutter/foundation.dart";

import "../config/recorder_pref_keys.dart";
import "../config/recorder_preferences.dart";
import "../data/models/recording_config.dart";

/// Owns the AR recording configuration: every user-facing toggle, its
/// persistence, and the assembled [RecordingConfig].
///
/// Extracted from `ArRecorderProvider` so the provider can stay focused on
/// session runtime + polling. The provider holds an instance, forwards its
/// `notifyListeners`, and exposes each toggle via thin delegating accessors so
/// the public API the UI binds to is unchanged.
/// Every setter below persists the new value through [RecorderPreferences] and
/// calls `notifyListeners`; rate setters snap out-of-range values to a
/// supported one first.
class ArRecordingConfigManager extends ChangeNotifier {
  /// Creates the manager over the host-supplied [preferences] store. Settings
  /// start on their defaults until [loadPersistedToggles] runs.
  ArRecordingConfigManager({required RecorderPreferences preferences})
    : _prefs = preferences;

  final RecorderPreferences _prefs;

  // Recording data toggles
  bool _recordImu = true;

  /// Whether IMU samples are recorded.
  bool get recordImu => _recordImu;
  set recordImu(bool value) {
    _recordImu = value;
    _prefs.set(RecorderPrefKeys.recordImu, value);
    notifyListeners();
  }

  bool _recordDepth = true;

  /// Whether depth maps are recorded.
  bool get recordDepth => _recordDepth;
  set recordDepth(bool value) {
    _recordDepth = value;
    _prefs.set(RecorderPrefKeys.recordDepth, value);
    notifyListeners();
  }

  bool _recordPointCloud = true;

  /// Whether point clouds are recorded.
  bool get recordPointCloud => _recordPointCloud;
  set recordPointCloud(bool value) {
    _recordPointCloud = value;
    _prefs.set(RecorderPrefKeys.recordPointCloud, value);
    notifyListeners();
  }

  bool _recordMesh = true;

  /// Whether the reconstructed mesh is recorded.
  bool get recordMesh => _recordMesh;
  set recordMesh(bool value) {
    _recordMesh = value;
    _prefs.set(RecorderPrefKeys.recordMesh, value);
    notifyListeners();
  }

  bool _recordRgb = true;

  /// Whether the RGB video track is recorded.
  bool get recordRgb => _recordRgb;
  set recordRgb(bool value) {
    _recordRgb = value;
    _prefs.set(RecorderPrefKeys.recordRgb, value);
    notifyListeners();
  }

  int _rgbHz = RecordingConfig.defaultSpatialHz;

  /// RGB frame rate in Hz. Setting it also moves [depthHz] and [pointCloudHz]
  /// while [syncHz] is on.
  int get rgbHz => _rgbHz;
  set rgbHz(int value) {
    _rgbHz = _sanitizeSpatialHz(value);
    _prefs.set(RecorderPrefKeys.rgbHz, _rgbHz);
    if (_syncHz) {
      _depthHz = _rgbHz;
      _pointCloudHz = _rgbHz;
      _prefs.set(RecorderPrefKeys.depthHz, _depthHz);
      _prefs.set(RecorderPrefKeys.pointCloudHz, _pointCloudHz);
    }
    notifyListeners();
  }

  int _depthHz = RecordingConfig.defaultSpatialHz;

  /// Depth frame rate in Hz. Setting it also moves [rgbHz] and [pointCloudHz]
  /// while [syncHz] is on.
  int get depthHz => _depthHz;
  set depthHz(int value) {
    final sanitizedValue = _sanitizeSpatialHz(value);
    _depthHz = sanitizedValue;
    _prefs.set(RecorderPrefKeys.depthHz, _depthHz);
    if (_syncHz) {
      _rgbHz = _depthHz;
      _pointCloudHz = _depthHz;
      _prefs.set(RecorderPrefKeys.rgbHz, _rgbHz);
      _prefs.set(RecorderPrefKeys.pointCloudHz, _pointCloudHz);
    }
    notifyListeners();
  }

  int _pointCloudHz = RecordingConfig.defaultSpatialHz;

  /// Point cloud rate in Hz. Setting it also moves [rgbHz] and [depthHz] while
  /// [syncHz] is on.
  int get pointCloudHz => _pointCloudHz;
  set pointCloudHz(int value) {
    final sanitizedValue = _sanitizeSpatialHz(value);
    _pointCloudHz = sanitizedValue;
    _prefs.set(RecorderPrefKeys.pointCloudHz, _pointCloudHz);
    if (_syncHz) {
      _rgbHz = _pointCloudHz;
      _depthHz = _pointCloudHz;
      _prefs.set(RecorderPrefKeys.rgbHz, _rgbHz);
      _prefs.set(RecorderPrefKeys.depthHz, _depthHz);
    }
    notifyListeners();
  }

  int _imuHz = RecordingConfig.supportedImuHz[1]; // 100

  /// IMU sample rate in Hz — one of [RecordingConfig.supportedImuHz].
  int get imuHz => _imuHz;
  set imuHz(int value) {
    final sanitizedValue = _sanitizeImuHz(value);
    _imuHz = sanitizedValue;
    _prefs.set(RecorderPrefKeys.imuHz, _imuHz);
    notifyListeners();
  }

  bool _syncHz = true;

  /// Whether the three spatial rates move together. Turning it on snaps
  /// [depthHz] and [pointCloudHz] to [rgbHz].
  bool get syncHz => _syncHz;
  set syncHz(bool value) {
    _syncHz = value;
    _prefs.set(RecorderPrefKeys.syncHz, value);
    if (_syncHz) {
      // Sync all spatial Hz to RGB's value
      _depthHz = _rgbHz;
      _pointCloudHz = _rgbHz;
      _prefs.set(RecorderPrefKeys.depthHz, _depthHz);
      _prefs.set(RecorderPrefKeys.pointCloudHz, _pointCloudHz);
    }
    notifyListeners();
  }

  bool _enableVoiceCommands = true;

  /// Whether voice commands can start and stop a recording.
  bool get enableVoiceCommands => _enableVoiceCommands;
  set enableVoiceCommands(bool value) {
    _enableVoiceCommands = value;
    _prefs.set(RecorderPrefKeys.enableVoiceCommands, value);
    notifyListeners();
  }

  bool _enableAudioCues = true;

  /// Whether audio cues play on session events.
  bool get enableAudioCues => _enableAudioCues;
  set enableAudioCues(bool value) {
    _enableAudioCues = value;
    _prefs.set(RecorderPrefKeys.enableAudioCues, value);
    notifyListeners();
  }

  bool _autoFocus = true;

  /// Whether the camera keeps auto-focusing during a take.
  bool get autoFocus => _autoFocus;
  set autoFocus(bool value) {
    _autoFocus = value;
    _prefs.set(RecorderPrefKeys.autoFocus, value);
    notifyListeners();
  }

  bool _autoExposure = true;

  /// Whether exposure stays automatic, rather than locking once it settles.
  /// See [RecordingConfig.autoExposure]. iOS ARKit path only.
  bool get autoExposure => _autoExposure;
  set autoExposure(bool value) {
    _autoExposure = value;
    _prefs.set(RecorderPrefKeys.autoExposure, value);
    notifyListeners();
  }

  // Default resolution is 1080p; the user can switch to 720p/4K in the settings
  // panel. Recording-rate options are resolution-specific (see
  // [RgbVideoResolution.spatialHzOptions]) and snapped into range on change.
  RgbVideoResolution _rgbVideoResolution = RgbVideoResolution.hd1080;

  /// RGB capture resolution. Changing it clamps [arkitFps] and the spatial
  /// rates into what the new resolution supports.
  RgbVideoResolution get rgbVideoResolution => _rgbVideoResolution;
  set rgbVideoResolution(RgbVideoResolution value) {
    _rgbVideoResolution = value;
    _prefs.set(RecorderPrefKeys.rgbVideoHeight, value.nominalHeight);
    // ARKit locks 4K capture to 30 fps. Clamp the ARKit session fps down so the
    // requested rate matches what the device will actually deliver (and so the
    // ARKit-IMU rate, which is bundled with arkitFps, stays in sync).
    if (_arkitFps > value.maxArkitFps) {
      arkitFps = value.maxArkitFps;
    }
    // Recording-rate options differ per resolution; snap the current rates into
    // the new resolution's set (e.g. 60 → 30 switching to 4K, 5/10 → 15
    // switching up to 1080p) so no out-of-range value lingers.
    _clampSpatialHzToResolution();
    notifyListeners();
  }

  /// Snaps the spatial rates into the option set the current resolution offers
  /// (4K → 5/10/15/30, else 15/30/60) so a value the resolution can't show
  /// never lingers as an unselected chip. Relies on each option list being a
  /// contiguous sub-range of [RecordingConfig.supportedSpatialHz], so clamping
  /// into [first, last] always lands on a valid member.
  void _clampSpatialHzToResolution() {
    final opts = _rgbVideoResolution.spatialHzOptions;
    _rgbHz = _rgbHz.clamp(opts.first, opts.last);
    _depthHz = _depthHz.clamp(opts.first, opts.last);
    _pointCloudHz = _pointCloudHz.clamp(opts.first, opts.last);
    _prefs.set(RecorderPrefKeys.rgbHz, _rgbHz);
    _prefs.set(RecorderPrefKeys.depthHz, _depthHz);
    _prefs.set(RecorderPrefKeys.pointCloudHz, _pointCloudHz);
  }

  // Defaults to 30 to match the default 4K resolution (4K is ARKit-locked to
  // 30 fps); user-selectable 30/60 at 720p/1080p, capped by the resolution.
  int _arkitFps = 30;

  /// ARKit session frame rate (iOS only), capped by [rgbVideoResolution].
  int get arkitFps => _arkitFps;
  set arkitFps(int value) {
    var sanitized = RecordingConfig.supportedArkitFps.contains(value)
        ? value
        : 60;
    // 4K is 30-fps only; never let the session fps exceed the resolution cap.
    sanitized = sanitized.clamp(0, _rgbVideoResolution.maxArkitFps);
    _arkitFps = sanitized;
    _prefs.set(RecorderPrefKeys.arkitFps, sanitized);
    notifyListeners();
  }

  bool _enableInertialDerived = true;

  /// Whether inertially-derived channels are recorded alongside raw IMU.
  bool get enableInertialDerived => _enableInertialDerived;
  set enableInertialDerived(bool value) {
    _enableInertialDerived = value;
    _prefs.set(RecorderPrefKeys.enableInertialDerived, value);
    notifyListeners();
  }

  /// The current settings, assembled into the config handed to the native side.
  RecordingConfig get recordingConfig => RecordingConfig(
    recordImu: _recordImu,
    recordDepth: _recordDepth,
    recordPointCloud: _recordPointCloud,
    recordMesh: _recordMesh,
    recordRgb: _recordRgb,
    rgbHz: _rgbHz,
    depthHz: _depthHz,
    pointCloudHz: _pointCloudHz,
    imuHz: _imuHz,
    rgbVideoResolution: _rgbVideoResolution,
    enableVoiceCommands: _enableVoiceCommands,
    enableAudioCues: _enableAudioCues,
    autoFocus: _autoFocus,
    autoExposure: _autoExposure,
    arkitFps: _arkitFps,
    enableInertialDerived: _enableInertialDerived,
  );

  /// Reloads every setting from [RecorderPreferences], sanitizing values that
  /// no longer fit the current resolution or supported-rate sets.
  void loadPersistedToggles() {
    _recordImu = _prefs.get<bool>(
      RecorderPrefKeys.recordImu,
      defaultValue: true,
    )!;
    _recordDepth = _prefs.get<bool>(
      RecorderPrefKeys.recordDepth,
      defaultValue: true,
    )!;
    _recordPointCloud = _prefs.get<bool>(
      RecorderPrefKeys.recordPointCloud,
      defaultValue: true,
    )!;
    _recordMesh = _prefs.get<bool>(
      RecorderPrefKeys.recordMesh,
      defaultValue: true,
    )!;
    _recordRgb = _prefs.get<bool>(
      RecorderPrefKeys.recordRgb,
      defaultValue: true,
    )!;
    _rgbHz = _sanitizeSpatialHz(
      _prefs.get<int>(
            RecorderPrefKeys.rgbHz,
            defaultValue: RecordingConfig.defaultSpatialHz,
          ) ??
          RecordingConfig.defaultSpatialHz,
    );
    _depthHz = _sanitizeSpatialHz(
      _prefs.get<int>(
            RecorderPrefKeys.depthHz,
            defaultValue: RecordingConfig.defaultSpatialHz,
          ) ??
          RecordingConfig.defaultSpatialHz,
    );
    _pointCloudHz = _sanitizeSpatialHz(
      _prefs.get<int>(
            RecorderPrefKeys.pointCloudHz,
            defaultValue: RecordingConfig.defaultSpatialHz,
          ) ??
          RecordingConfig.defaultSpatialHz,
    );
    _imuHz = _sanitizeImuHz(
      _prefs.get<int>(RecorderPrefKeys.imuHz, defaultValue: 100) ?? 100,
    );
    _syncHz = _prefs.get<bool>(RecorderPrefKeys.syncHz, defaultValue: true)!;
    _enableVoiceCommands = _prefs.get<bool>(
      RecorderPrefKeys.enableVoiceCommands,
      defaultValue: true,
    )!;
    _enableAudioCues = _prefs.get<bool>(
      RecorderPrefKeys.enableAudioCues,
      defaultValue: true,
    )!;
    _autoFocus = _prefs.get<bool>(
      RecorderPrefKeys.autoFocus,
      defaultValue: true,
    )!;
    _autoExposure = _prefs.get<bool>(
      RecorderPrefKeys.autoExposure,
      defaultValue: true,
    )!;
    _rgbVideoResolution = RgbVideoResolution.fromNominalHeight(
      _prefs.get<int>(
            RecorderPrefKeys.rgbVideoHeight,
            defaultValue: RgbVideoResolution.hd1080.nominalHeight,
          ) ??
          RgbVideoResolution.hd1080.nominalHeight,
    );
    final loadedArkitFps =
        _prefs.get<int>(RecorderPrefKeys.arkitFps, defaultValue: 60) ?? 60;
    _arkitFps = RecordingConfig.supportedArkitFps.contains(loadedArkitFps)
        ? loadedArkitFps
        : 60;
    // 4K is 30-fps only — never let a persisted 60 survive against a 4K
    // resolution (the resolution setter enforces this on change; do it on load
    // too for upgrades / tampered stores).
    _arkitFps = _arkitFps.clamp(0, _rgbVideoResolution.maxArkitFps);
    _prefs.set(RecorderPrefKeys.arkitFps, _arkitFps);
    // Snap persisted spatial rates into the resolution's option set (e.g. a
    // legacy 60 Hz against 4K, or 5/10 Hz against 1080p).
    _clampSpatialHzToResolution();
    _enableInertialDerived = _prefs.get<bool>(
      RecorderPrefKeys.enableInertialDerived,
      defaultValue: true,
    )!;
  }

  int _sanitizeSpatialHz(int value) {
    if (RecordingConfig.supportedSpatialHz.contains(value)) return value;
    return RecordingConfig.defaultSpatialHz;
  }

  int _sanitizeImuHz(int value) {
    if (RecordingConfig.supportedImuHz.contains(value)) return value;
    return RecordingConfig.supportedImuHz[1]; // 100
  }
}
