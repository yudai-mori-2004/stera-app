# Changelog

## 0.0.2

Metadata and licence only. No API or behaviour changes.

- **Relicensed from MIT to Apache 2.0**, matching the rest of the Stera project
  and `stera-sdk`. 0.0.1 remains available under MIT; that grant is irrevocable
  for anyone who already took it.
- `repository` and `issue_tracker` now point at
  https://github.com/fpv-labs/stera-app. The 0.0.1 URLs were unreachable.
- Shortened the package description to fit pub.dev's 180-character limit.

## 0.0.1

Initial release, extracted from the Stera mobile app.

- ARKit (iOS) and ARCore (Android) capture sessions writing an MCAP dataset:
  RGB video, depth, point cloud, mesh and IMU.
- `ArRecorderService` — the method-channel facade, with the iOS hot paths
  (`startRecording`, `stopRecording`, `getRecordingState`, …) going through FFI.
- `ArRecorderProvider` / `ArRecordingConfigManager` — session state and the
  recording settings, persisted through a host-supplied `RecorderPreferences`.
- Recording support services: audio cues, voice commands, battery monitoring.
- iOS builds under both Swift Package Manager and CocoaPods.
