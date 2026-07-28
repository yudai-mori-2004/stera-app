import "../enums/rgb_video_resolution.dart";

export "../enums/rgb_video_resolution.dart";

/// Configuration for which data channels to record into the MCAP file.
class RecordingConfig {
  /// All selectable spatial stream rates across resolutions, ascending. The
  /// per-resolution subset shown in the UI comes from
  /// [RgbVideoResolution.spatialHzOptions]; this superset is what sanitization
  /// validates against.
  static const supportedSpatialHz = <int>[5, 10, 15, 30, 60];

  /// Default spatial rate when nothing is persisted. Kept separate from the
  /// list order so adding lower rates can't shift the default off 15 Hz.
  static const defaultSpatialHz = 30;

  /// The IMU rates the recorder accepts, in Hz.
  static const supportedImuHz = <int>[50, 100];

  /// The ARKit session frame rates the recorder accepts, in fps.
  static const supportedArkitFps = <int>[30, 60];

  /// Whether IMU samples are recorded.
  final bool recordImu;

  /// Whether depth maps are recorded.
  final bool recordDepth;

  /// Whether point clouds are recorded.
  final bool recordPointCloud;

  /// Whether the reconstructed mesh is recorded.
  final bool recordMesh;

  /// Whether the RGB video track is recorded.
  final bool recordRgb;

  /// RGB frame rate, in Hz.
  final int rgbHz;

  /// Depth frame rate, in Hz.
  final int depthHz;

  /// Point cloud rate, in Hz.
  final int pointCloudHz;

  /// IMU sample rate, in Hz.
  final int imuHz;

  /// RGB capture resolution.
  final RgbVideoResolution rgbVideoResolution;

  /// Whether voice commands can start and stop a recording.
  final bool enableVoiceCommands;

  /// Whether audio cues play on session events.
  final bool enableAudioCues;

  /// Whether the camera keeps auto-focusing during a take.
  final bool autoFocus;

  /// When true, the camera adjusts exposure automatically. When false, exposure
  /// is locked after it settles so brightness stays constant across the take
  /// (useful for photogrammetry / COLMAP). iOS ARKit path only.
  final bool autoExposure;

  /// ARKit session frame rate (iOS only), in fps.
  final int arkitFps;

  /// Whether inertially-derived channels are recorded alongside raw IMU.
  final bool enableInertialDerived;

  /// Creates a configuration; every channel is on and at its default rate
  /// unless overridden.
  const RecordingConfig({
    this.recordImu = true,
    this.recordDepth = true,
    this.recordPointCloud = true,
    this.recordMesh = true,
    this.recordRgb = true,
    this.rgbHz = defaultSpatialHz,
    this.depthHz = defaultSpatialHz,
    this.pointCloudHz = defaultSpatialHz,
    this.imuHz = 100,
    this.rgbVideoResolution = RgbVideoResolution.hd1080,
    this.enableVoiceCommands = true,
    this.enableAudioCues = true,
    this.autoFocus = true,
    this.autoExposure = true,
    this.arkitFps = 30,
    this.enableInertialDerived = true,
  });

  /// Serializes the config into the map the native session expects. The keys
  /// are part of the native contract — see `ArRecorderMethodChannelHandler`.
  Map<String, dynamic> toMap() => {
    "recordImu": recordImu,
    "recordDepth": recordDepth,
    "recordPointCloud": recordPointCloud,
    "recordMesh": recordMesh,
    "recordRgb": recordRgb,
    "rgbHz": rgbHz,
    "depthHz": depthHz,
    "pointCloudHz": pointCloudHz,
    "imuHz": imuHz,
    "rgbVideoHeight": rgbVideoResolution.nominalHeight,
    "enableVoiceCommands": enableVoiceCommands,
    "enableAudioCues": enableAudioCues,
    "autoFocus": autoFocus,
    "autoExposure": autoExposure,
    "arkitFps": arkitFps,
    "enableInertialDerived": enableInertialDerived,
  };
}
