import "package:objective_c/objective_c.dart";

import "../data/models/recording_config.dart";
import "generated/ios_ar_recorder_objc_bindings.dart";

class IosArRecorderFfiResult {
  final bool success;
  final bool supported;
  final String? state;
  final String? trackingState;
  final bool? isRecording;
  final bool? isPaused;
  final bool? depthSupported;
  final bool? meshSupported;
  final int? recordingDurationMs;
  final int? frameCount;
  final int? textureId;
  final String? cameraResolution;
  final String? recordingResolution;
  final bool? isLowQualityMode;
  final String? lowQualityReason;
  final bool? isFinalizationInProgress;
  final String? outputDirectory;
  final double? durationSeconds;
  final int? framesRecorded;
  final int? imuSamples;
  final int? recordingHz;
  final String? error;

  const IosArRecorderFfiResult({
    required this.success,
    required this.supported,
    this.state,
    this.trackingState,
    this.isRecording,
    this.isPaused,
    this.depthSupported,
    this.meshSupported,
    this.recordingDurationMs,
    this.frameCount,
    this.textureId,
    this.cameraResolution,
    this.recordingResolution,
    this.isLowQualityMode,
    this.lowQualityReason,
    this.isFinalizationInProgress,
    this.outputDirectory,
    this.durationSeconds,
    this.framesRecorded,
    this.imuSamples,
    this.recordingHz,
    this.error,
  });

  factory IosArRecorderFfiResult.fromNative(ARFRecorderResult native) {
    return IosArRecorderFfiResult(
      success: native.success,
      supported: native.supported,
      state: _emptyToNull(native.state.toDartString()),
      trackingState: _emptyToNull(native.trackingState.toDartString()),
      isRecording: native.isRecording,
      isPaused: native.isPaused,
      depthSupported: native.depthSupported,
      meshSupported: native.meshSupported,
      recordingDurationMs: _sentinelIntToNull(native.recordingDurationMs),
      frameCount: _sentinelIntToNull(native.frameCount),
      textureId: _sentinelIntToNull(native.textureId),
      cameraResolution: _emptyToNull(native.cameraResolution.toDartString()),
      recordingResolution: _emptyToNull(
        native.recordingResolution.toDartString(),
      ),
      isLowQualityMode: native.isLowQualityMode,
      lowQualityReason: _emptyToNull(native.lowQualityReason.toDartString()),
      isFinalizationInProgress: native.isFinalizationInProgress,
      outputDirectory: _emptyToNull(native.outputDirectory.toDartString()),
      durationSeconds: native.durationSeconds >= 0
          ? native.durationSeconds
          : null,
      framesRecorded: _sentinelIntToNull(native.framesRecorded),
      imuSamples: _sentinelIntToNull(native.imuSamples),
      recordingHz: _sentinelIntToNull(native.recordingHz),
      error: _emptyToNull(native.errorMessage.toDartString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "success": success,
      "supported": supported,
      "state": state,
      "trackingState": trackingState,
      "isRecording": isRecording,
      "isPaused": isPaused,
      "depthSupported": depthSupported,
      "meshSupported": meshSupported,
      "recordingDuration": recordingDurationMs,
      "frameCount": frameCount,
      "textureId": textureId,
      "cameraResolution": cameraResolution,
      "recordingResolution": recordingResolution,
      "isLowQualityMode": isLowQualityMode,
      "lowQualityReason": lowQualityReason,
      "isFinalizationInProgress": isFinalizationInProgress,
      "outputDirectory": outputDirectory,
      "durationSeconds": durationSeconds,
      "framesRecorded": framesRecorded,
      "imuSamples": imuSamples,
      "recordingHz": recordingHz,
      "error": error,
    };
  }

  static int? _sentinelIntToNull(int value) => value >= 0 ? value : null;

  static String? _emptyToNull(String value) => value.isEmpty ? null : value;
}

class IosArRecorderFfiClient {
  static final ARRecorderInterop _interop = ARRecorderInterop.sharedInterop();

  static IosArRecorderFfiResult startRecording(RecordingConfig config) {
    final nativeConfig = ARFRecordingConfig()
      ..recordImu = config.recordImu
      ..recordDepth = config.recordDepth
      ..recordPointCloud = config.recordPointCloud
      ..recordMesh = config.recordMesh
      ..recordRgb = config.recordRgb
      ..rgbHz = config.rgbHz
      ..depthHz = config.depthHz
      ..pointCloudHz = config.pointCloudHz
      ..imuHz = config.imuHz
      ..rgbVideoHeight = config.rgbVideoResolution.nominalHeight
      ..autoFocus = config.autoFocus
      ..arkitFps = config.arkitFps
      ..enableInertialDerived = config.enableInertialDerived;

    return IosArRecorderFfiResult.fromNative(
      _interop.startRecordingWithConfig(nativeConfig),
    );
  }

  static IosArRecorderFfiResult pauseRecording() {
    return IosArRecorderFfiResult.fromNative(_interop.pauseRecording());
  }

  static IosArRecorderFfiResult resumeRecording() {
    return IosArRecorderFfiResult.fromNative(_interop.resumeRecording());
  }

  static IosArRecorderFfiResult cancelRecording() {
    return IosArRecorderFfiResult.fromNative(_interop.cancelRecording());
  }

  static IosArRecorderFfiResult stopRecording() {
    return IosArRecorderFfiResult.fromNative(_interop.stopRecording());
  }

  static IosArRecorderFfiResult getRecordingState() {
    return IosArRecorderFfiResult.fromNative(_interop.getRecordingState());
  }

  static bool checkArAvailability() {
    return IosArRecorderFfiResult.fromNative(
      _interop.checkArAvailability(),
    ).supported;
  }
}
