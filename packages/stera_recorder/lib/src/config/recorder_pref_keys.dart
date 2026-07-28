/// Persisted keys for the recording settings.
///
/// These strings are shipped state: they are the literal keys written into the
/// host app's `RecorderPreferences` store. Once a version ships, a key's value
/// must never change — renaming one silently resets that setting for every user
/// who upgrades.
class RecorderPrefKeys {
  const RecorderPrefKeys._();

  /// Whether IMU samples are written to the dataset.
  static const String recordImu = "recording_toggle_imu";

  /// Whether depth maps are written to the dataset.
  static const String recordDepth = "recording_toggle_depth";

  /// Whether point clouds are written to the dataset.
  static const String recordPointCloud = "recording_toggle_point_cloud";

  /// Whether the reconstructed mesh is written to the dataset.
  static const String recordMesh = "recording_toggle_mesh";

  /// Whether the RGB video track is written to the dataset.
  static const String recordRgb = "recording_toggle_rgb";

  /// RGB frame rate, in Hz.
  static const String rgbHz = "recording_rgb_hz";

  /// Depth frame rate, in Hz.
  static const String depthHz = "recording_depth_hz";

  /// Point cloud rate, in Hz.
  static const String pointCloudHz = "recording_point_cloud_hz";

  /// IMU sample rate, in Hz.
  static const String imuHz = "recording_imu_hz";

  /// Whether the three spatial rates move together.
  static const String syncHz = "recording_sync_hz";

  /// Nominal height of the RGB video resolution (720, 1080, 2160).
  static const String rgbVideoHeight = "recording_rgb_video_height";

  /// Whether voice commands can start and stop a recording.
  static const String enableVoiceCommands = "recording_toggle_voice_commands";

  /// Whether audio cues play on session events.
  static const String enableAudioCues = "recording_toggle_audio_cues";

  /// Whether the camera keeps auto-focusing during a take.
  static const String autoFocus = "recording_toggle_auto_focus";

  /// Whether exposure stays automatic, rather than locking once it settles.
  static const String autoExposure = "recording_toggle_auto_exposure";

  /// ARKit session frame rate (iOS only), in fps.
  static const String arkitFps = "recording_arkit_fps";

  /// Whether inertially-derived channels are recorded alongside raw IMU.
  static const String enableInertialDerived = "recording_inertial_derived";
}
