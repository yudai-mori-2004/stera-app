import "package:flutter_test/flutter_test.dart";
import "package:stera_recorder/stera_recorder.dart";

void main() {
  group("RecorderPrefKeys", () {
    // These strings are shipped state: a rename silently resets that setting
    // for every user who upgrades. Pin them.
    test("key values never change", () {
      expect(RecorderPrefKeys.recordImu, "recording_toggle_imu");
      expect(RecorderPrefKeys.recordDepth, "recording_toggle_depth");
      expect(RecorderPrefKeys.recordPointCloud, "recording_toggle_point_cloud");
      expect(RecorderPrefKeys.recordMesh, "recording_toggle_mesh");
      expect(RecorderPrefKeys.recordRgb, "recording_toggle_rgb");
      expect(RecorderPrefKeys.rgbHz, "recording_rgb_hz");
      expect(RecorderPrefKeys.depthHz, "recording_depth_hz");
      expect(RecorderPrefKeys.pointCloudHz, "recording_point_cloud_hz");
      expect(RecorderPrefKeys.imuHz, "recording_imu_hz");
      expect(RecorderPrefKeys.syncHz, "recording_sync_hz");
      expect(RecorderPrefKeys.rgbVideoHeight, "recording_rgb_video_height");
      expect(
        RecorderPrefKeys.enableVoiceCommands,
        "recording_toggle_voice_commands",
      );
      expect(RecorderPrefKeys.enableAudioCues, "recording_toggle_audio_cues");
      expect(RecorderPrefKeys.autoFocus, "recording_toggle_auto_focus");
      expect(RecorderPrefKeys.autoExposure, "recording_toggle_auto_exposure");
      expect(RecorderPrefKeys.arkitFps, "recording_arkit_fps");
      expect(
        RecorderPrefKeys.enableInertialDerived,
        "recording_inertial_derived",
      );
    });
  });

  group("InMemoryRecorderPreferences", () {
    test("returns the caller's default until a value is written", () async {
      final prefs = InMemoryRecorderPreferences();

      expect(
        prefs.get<bool>(RecorderPrefKeys.recordImu, defaultValue: true),
        isTrue,
      );
      expect(prefs.get<int>(RecorderPrefKeys.rgbHz), isNull);

      await prefs.set(RecorderPrefKeys.recordImu, false);
      expect(
        prefs.get<bool>(RecorderPrefKeys.recordImu, defaultValue: true),
        isFalse,
      );
    });
  });

  group("RecordingConfig.toMap", () {
    test("carries every field under the native contract's keys", () {
      final map = const RecordingConfig(
        recordImu: false,
        rgbHz: 15,
        depthHz: 10,
        pointCloudHz: 5,
        imuHz: 50,
        rgbVideoResolution: RgbVideoResolution.uhd4k,
        arkitFps: 30,
      ).toMap();

      expect(map["recordImu"], isFalse);
      expect(map["recordDepth"], isTrue);
      expect(map["rgbHz"], 15);
      expect(map["depthHz"], 10);
      expect(map["pointCloudHz"], 5);
      expect(map["imuHz"], 50);
      // The native side takes a nominal height, not the enum.
      expect(map["rgbVideoHeight"], 2160);
      expect(map["arkitFps"], 30);
      expect(map["enableInertialDerived"], isTrue);
    });
  });

  group("ArRecordingConfigManager", () {
    test("persists a toggle and notifies", () async {
      final prefs = InMemoryRecorderPreferences();
      final manager = ArRecordingConfigManager(preferences: prefs);
      var notified = 0;
      manager.addListener(() => notified++);

      manager.recordMesh = false;

      expect(notified, 1);
      expect(prefs.get<bool>(RecorderPrefKeys.recordMesh), isFalse);
      expect(manager.recordingConfig.recordMesh, isFalse);
    });

    test("snaps an unsupported spatial rate to the default", () {
      final manager = ArRecordingConfigManager(
        preferences: InMemoryRecorderPreferences(),
      );

      manager.rgbHz = 7;

      expect(manager.rgbHz, RecordingConfig.defaultSpatialHz);
    });

    test("syncHz moves depth and point cloud with rgb", () {
      final manager = ArRecordingConfigManager(
        preferences: InMemoryRecorderPreferences(),
      )..syncHz = true;

      manager.rgbHz = 60;

      expect(manager.depthHz, 60);
      expect(manager.pointCloudHz, 60);
    });

    test("switching to 4K clamps fps and the spatial rates into range", () {
      final manager =
          ArRecordingConfigManager(preferences: InMemoryRecorderPreferences())
            ..arkitFps = 60
            ..rgbHz = 60;

      manager.rgbVideoResolution = RgbVideoResolution.uhd4k;

      // 4K is 30-fps only, and its rate options top out at 30.
      expect(manager.arkitFps, 30);
      expect(manager.rgbHz, 30);
      expect(manager.depthHz, 30);
      expect(manager.pointCloudHz, 30);
    });

    test("loadPersistedToggles reads back what the setters wrote", () {
      final prefs = InMemoryRecorderPreferences();
      ArRecordingConfigManager(preferences: prefs)
        ..recordDepth = false
        ..imuHz = 50
        ..enableAudioCues = false;

      final reloaded = ArRecordingConfigManager(preferences: prefs)
        ..loadPersistedToggles();

      expect(reloaded.recordDepth, isFalse);
      expect(reloaded.imuHz, 50);
      expect(reloaded.enableAudioCues, isFalse);
    });
  });
}
