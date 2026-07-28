# stera_recorder

An ARKit (iOS) / ARCore (Android) capture session for Flutter that writes an
MCAP dataset — RGB video, depth, point cloud, mesh and IMU — plus the Dart API
you drive it with.

This is a Flutter **plugin**: the Swift and Kotlin implementations ship here and
register themselves through `GeneratedPluginRegistrant`. There is no manual
wiring in your `SceneDelegate` / `MainActivity`.

## Platform support

| Platform | Minimum          | Notes                                            |
| -------- | ---------------- | ------------------------------------------------ |
| iOS      | 14.0             | ARKit. Depth and mesh need a LiDAR device.       |
| Android  | API 24           | ARCore 1.44. Depth depends on device support.    |

A physical device is required — there is no AR session on the iOS Simulator or
the Android emulator.

## Install

```bash
flutter pub add stera_recorder
```

## Setup

**iOS** — add the usage descriptions to `ios/Runner/Info.plist`. The camera key
is always required; the microphone and speech keys are only needed if you leave
voice commands enabled.

```xml
<key>NSCameraUsageDescription</key>
<string>Used to record AR sessions.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Used for voice commands during recording.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Used to recognise recording voice commands.</string>
```

**Android** — nothing to add. The plugin's manifest merges in `CAMERA`,
`HIGH_SAMPLING_RATE_SENSORS`, the optional `android.hardware.camera.ar` feature
and the `com.google.ar.core` meta-data. Your app needs `minSdk 24` or higher.

The plugin only ever *checks* permissions; requesting them is your app's job.

## Usage

You supply persistence and permissions, then build your own UI on top of
`ArRecorderProvider` — a `ChangeNotifier` holding the session state.

```dart
import "package:permission_handler/permission_handler.dart";
import "package:stera_recorder/stera_recorder.dart";

class AppRecorderPermissions implements RecorderPermissions {
  const AppRecorderPermissions();

  @override
  Future<bool> isCameraPermissionGranted() async =>
      (await Permission.camera.status).isGranted;

  @override
  Future<bool> openSettings() => openAppSettings();
}

final recorder = ArRecorderProvider(
  // Swap InMemoryRecorderPreferences for a RecorderPreferences backed by your
  // own key-value store to persist the recording settings across launches.
  preferences: InMemoryRecorderPreferences(),
  permissions: const AppRecorderPermissions(),
);

await recorder.initializeSession();
await recorder.startRecording();
// …
await recorder.stopRecording();
print(recorder.outputDirectory); // the MCAP dataset
```

Render the preview with `Texture(textureId: recorder.textureId!)` once
`recorder.textureId` is non-null, and rebuild on the provider — see
`example/lib/main.dart` for the whole screen in ~230 lines.

## What you get

- `ArRecorderProvider` — the `ChangeNotifier` your UI binds to: session
  lifecycle, tracking state, preview texture, durations, and the recording
  settings forwarded from the config manager.
- `ArRecordingConfigManager` — the recording settings and their persistence
  through your `RecorderPreferences`.
- `ArRecorderService` — the method-channel / FFI facade, if you'd rather drive
  the native session yourself.
- `RecordingConfig`, `RgbVideoResolution`, `ArRecorderState`, `ArTrackingState`
  — the data types those APIs speak.

Output is a directory of [MCAP](https://mcap.dev) files: the RGB track as
encoded video, with depth, point cloud, mesh and IMU on their own channels,
timestamped against the AR session clock.

## Layout

```
lib/src/
  channels/    ar_recorder channel name + method enum (shipped native contract)
  service/     ArRecorderService — the method-channel / FFI facade
  ffi/         iOS interop: the ffigen output plus its typed wrapper
  data/        RecordingConfig and the recorder/tracking/resolution enums
  config/      RecorderPreferences + RecorderPermissions (host-supplied)
  managers/    ArRecordingConfigManager — the settings and their persistence
  providers/   ArRecorderProvider — the ChangeNotifier the UI binds to
  services/    audio cues, voice commands, battery monitoring
ios/           Swift Package (stera_recorder/Sources/) plus the podspec that
               compiles the same sources: session, frame pipeline, encoders,
               MCAP writers
android/       Kotlin: the same triad, plus the ARCore dependency
ffi/           ARRecorderInterop.h — ffigen input only, not compiled into the pod
```

`RecorderPrefKeys` holds the persisted setting keys. **They are shipped state —
never change a value**, or every user's recording settings reset on upgrade.

## Example

`example/` is a one-screen app — permission, preview, record, stop:

```bash
cd example && flutter run
```

It needs a physical ARKit or ARCore device.

## Native contract

The channel name (`ar_recorder`) and the method names in `ArRecorderMethod` must
stay in lockstep with `ArRecorderMethodChannelHandler.swift` / `.kt`.

On iOS the hot paths (`startRecording`, `stopRecording`, `getRecordingState`, …)
bypass the method channel and go through FFI. The generated bindings look
classes up by their Objective-C runtime name, which is why
`ArRecorderInterop.swift` pins them with explicit `@objc(ARFRecordingConfig)`
style annotations — without those the names would carry the Swift module prefix
and every FFI call would fail at class lookup.

Regenerate the bindings after changing `ffi/ARRecorderInterop.h`:

```bash
dart run tool/generate_ar_recorder_objc_bindings.dart
```

## Known limitations

- **Built-in Kotlin.** `android/build.gradle` still applies the Kotlin Gradle
  Plugin itself. Moving to AGP's built-in Kotlin — which Flutter warns about
  today and will eventually enforce — needs AGP 9.

iOS builds under both Swift Package Manager and CocoaPods: `ios/stera_recorder`
is a Swift package whose Objective-C `ObjCTryBlock` shim lives in its own target
(SwiftPM can't mix the two in one module), and `stera_recorder.podspec` compiles
the same sources for the CocoaPods path.

## License

Apache 2.0 — see [LICENSE](LICENSE).
