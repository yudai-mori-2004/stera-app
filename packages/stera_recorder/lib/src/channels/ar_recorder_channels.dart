import "package:flutter/services.dart";

/// The AR Recorder platform channel. The name is part of the shipped native
/// contract (it must match the `channelName`/`CHANNEL_NAME` constants in
/// `ArRecorderMethodChannelHandler.swift` / `.kt`) — never rename the value.
class ArRecorderChannel {
  const ArRecorderChannel._();

  static const String name = "ar_recorder";

  static MethodChannel get channel => const MethodChannel(name);
}

/// All available methods for the AR Recorder platform channel.
/// The last two are native → Dart notifications, not invocable methods.
enum ArRecorderMethod {
  initializeSession("initializeSession"),
  startRecording("startRecording"),
  pauseRecording("pauseRecording"),
  resumeRecording("resumeRecording"),
  cancelRecording("cancelRecording"),
  stopRecording("stopRecording"),
  getRecordingState("getRecordingState"),
  checkArAvailability("checkArAvailability"),
  disposeSession("disposeSession"),
  lowStorageWarning("lowStorageWarning"),
  storageCritical("storageCritical");

  final String methodName;
  const ArRecorderMethod(this.methodName);
}
