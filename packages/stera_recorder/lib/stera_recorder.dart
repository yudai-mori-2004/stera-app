/// ARKit and ARCore capture for Flutter, recorded to an MCAP dataset.
///
/// Owns the ARKit/ARCore capture session, the MCAP dataset writers, and the
/// Dart-side session API. The host app supplies persistence and permissions via
/// [RecorderPreferences] / [RecorderPermissions] and builds its own UI on top of
/// [ArRecorderProvider].
library;

export "src/channels/ar_recorder_channels.dart";
export "src/config/recorder_permissions.dart";
export "src/config/recorder_pref_keys.dart";
export "src/config/recorder_preferences.dart";
export "src/data/enums/ar_recorder_state.dart";
export "src/data/enums/ar_tracking_state.dart";
export "src/data/enums/rgb_video_resolution.dart";
export "src/data/models/recording_config.dart";
export "src/managers/ar_recording_config_manager.dart";
export "src/providers/ar_recorder_provider.dart";
export "src/service/ar_recorder_service.dart";
export "src/services/audio_cue_service.dart";
export "src/services/battery_monitor_service.dart";
export "src/services/voice_command_service.dart";
