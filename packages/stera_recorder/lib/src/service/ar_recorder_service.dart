import "dart:developer" as dev;

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

import "../channels/ar_recorder_channels.dart";
import "../data/models/recording_config.dart";
import "../ffi/ios_ar_recorder_ffi.dart";

class ArRecorderServiceException implements Exception {
  final String method;
  final String message;
  final String? code;

  const ArRecorderServiceException({
    required this.method,
    required this.message,
    this.code,
  });

  @override
  String toString() => "$method failed: $message";
}

/// Service for AR recording operations via platform channel.
class ArRecorderService {
  static const _channel = MethodChannel(ArRecorderChannel.name);
  static bool get _useIosInterop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<Map<String, dynamic>?> _invokeMapMethod(
    String methodName, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _channel.invokeMethod<Map>(methodName, arguments);
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> _invokeArRecorderMethod(
    ArRecorderMethod method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      return await _invokeMapMethod(method.methodName, arguments);
    } on PlatformException catch (e) {
      final message = e.message ?? "Platform call failed";
      dev.log(
        "❌ ArRecorderService: ${method.methodName} failed [${e.code}] $message",
      );
      throw ArRecorderServiceException(
        method: method.methodName,
        message: message,
        code: e.code,
      );
    }
  }

  /// Initializes the ARCore session and prepares for recording.
  /// Returns a map containing initialization result.
  static Future<Map<String, dynamic>?> initializeSession({
    Map<String, dynamic>? preferences,
  }) async {
    try {
      dev.log("📷 ArRecorderService: Initializing session...");
      final result = await _invokeArRecorderMethod(
        ArRecorderMethod.initializeSession,
        preferences,
      );

      if (result == null) {
        dev.log("❌ ArRecorderService: Received null from initializeSession");
        return null;
      }

      final response = result;
      if (response["success"] == true) {
        dev.log("✅ ArRecorderService: Session initialized successfully");
      } else {
        dev.log(
          "❌ ArRecorderService: Session initialization failed: ${response["error"]}",
        );
      }

      return response;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error initializing session: $e");
      return null;
    }
  }

  /// Starts recording AR data.
  /// Only succeeds if the session is ready and tracking is stable.
  static Future<Map<String, dynamic>?> startRecording({
    RecordingConfig config = const RecordingConfig(),
  }) async {
    try {
      dev.log("📷 ArRecorderService: Starting recording...");
      final result = _useIosInterop
          ? IosArRecorderFfiClient.startRecording(config).toMap()
          : await _invokeArRecorderMethod(
              ArRecorderMethod.startRecording,
              config.toMap(),
            );

      if (result == null) {
        dev.log("❌ ArRecorderService: Received null from startRecording");
        return null;
      }

      final response = result;
      if (response["success"] == true) {
        dev.log(
          "✅ ArRecorderService: Recording started: ${response["outputDirectory"]}",
        );
      } else {
        dev.log(
          "❌ ArRecorderService: Failed to start recording: ${response["error"]}",
        );
      }

      return response;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error starting recording: $e");
      return null;
    }
  }

  /// Pauses recording while keeping the same output session active.
  static Future<Map<String, dynamic>?> pauseRecording() async {
    try {
      dev.log("📷 ArRecorderService: Pausing recording...");
      final result = _useIosInterop
          ? IosArRecorderFfiClient.pauseRecording().toMap()
          : await _invokeArRecorderMethod(ArRecorderMethod.pauseRecording);
      if (result == null) {
        dev.log("❌ ArRecorderService: Received null from pauseRecording");
        return null;
      }
      return result;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error pausing recording: $e");
      rethrow;
    }
  }

  /// Resumes a paused recording.
  static Future<Map<String, dynamic>?> resumeRecording() async {
    try {
      dev.log("📷 ArRecorderService: Resuming recording...");
      final result = _useIosInterop
          ? IosArRecorderFfiClient.resumeRecording().toMap()
          : await _invokeArRecorderMethod(ArRecorderMethod.resumeRecording);
      if (result == null) {
        dev.log("❌ ArRecorderService: Received null from resumeRecording");
        return null;
      }
      return result;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error resuming recording: $e");
      rethrow;
    }
  }

  /// Cancels recording and discards the current session.
  static Future<Map<String, dynamic>?> cancelRecording() async {
    try {
      dev.log("📷 ArRecorderService: Cancelling recording...");
      final result = _useIosInterop
          ? IosArRecorderFfiClient.cancelRecording().toMap()
          : await _invokeArRecorderMethod(ArRecorderMethod.cancelRecording);
      if (result == null) {
        dev.log("❌ ArRecorderService: Received null from cancelRecording");
        return null;
      }
      return result;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error cancelling recording: $e");
      rethrow;
    }
  }

  /// Stops recording and finalizes all output files.
  static Future<Map<String, dynamic>?> stopRecording() async {
    try {
      dev.log("📷 ArRecorderService: Stopping recording...");
      final result = _useIosInterop
          ? IosArRecorderFfiClient.stopRecording().toMap()
          : await _invokeArRecorderMethod(ArRecorderMethod.stopRecording);

      if (result == null) {
        dev.log("❌ ArRecorderService: Received null from stopRecording");
        return null;
      }

      final response = result;
      if (response["success"] == true) {
        dev.log(
          "✅ ArRecorderService: Recording stopped: ${response["outputDirectory"]}",
        );
        dev.log(
          "📊 Stats: durationSeconds=${response["durationSeconds"]}, framesRecorded=${response["framesRecorded"]}, imuSamples=${response["imuSamples"]}, depthSupported=${response["depthSupported"]}",
        );
      } else {
        dev.log(
          "❌ ArRecorderService: Failed to stop recording: ${response["error"]}",
        );
      }

      return response;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error stopping recording: $e");
      return null;
    }
  }

  /// Gets the current recording state and session information.
  static Future<Map<String, dynamic>?> getRecordingState() async {
    try {
      final result = _useIosInterop
          ? IosArRecorderFfiClient.getRecordingState().toMap()
          : await _invokeArRecorderMethod(ArRecorderMethod.getRecordingState);

      if (result == null) {
        return null;
      }
      return result;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error getting recording state: $e");
      rethrow;
    }
  }

  /// Checks if ARCore is supported on this device.
  /// Returns true if AR is supported, false otherwise.
  static Future<bool> checkArAvailability() async {
    try {
      if (_useIosInterop) {
        return IosArRecorderFfiClient.checkArAvailability();
      }
      final result = await _invokeArRecorderMethod(
        ArRecorderMethod.checkArAvailability,
      );
      return result?["supported"] as bool? ?? false;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error checking AR availability: $e");
      return false;
    }
  }

  /// Disposes the ARCore session and releases all resources.
  static Future<bool> disposeSession() async {
    try {
      dev.log("📷 ArRecorderService: Disposing session...");
      final result = await _invokeArRecorderMethod(
        ArRecorderMethod.disposeSession,
      );

      if (result == null) {
        return false;
      }

      final success = result["success"] == true;

      if (success) {
        dev.log("✅ ArRecorderService: Session disposed");
      } else {
        dev.log("❌ ArRecorderService: Failed to dispose session");
      }

      return success;
    } catch (e) {
      dev.log("❌ ArRecorderService: Error disposing session: $e");
      return false;
    }
  }
}
