import "package:permission_handler/permission_handler.dart";
import "dart:developer" as dev;

import "package:flutter/services.dart";

class PermissionService {
  /// Gets the current notification permission status without requesting.
  static Future<PermissionStatus> getNotificationPermissionStatus() async {
    return await Permission.notification.status;
  }

  static Future<bool> hasNotificationPermission() async {
    final status = await Permission.notification.status;
    dev.log("Notification permission status: $status");

    switch (status) {
      case PermissionStatus.granted:
        return true;
      case PermissionStatus.denied:
        final result = await Permission.notification.request();
        return result.isGranted;
      case PermissionStatus.permanentlyDenied:
      case PermissionStatus.restricted:
      case PermissionStatus.limited:
      default:
        return false;
    }
  }

  /// In-flight [ensureCameraPermission] so parallel callers do not trigger
  /// concurrent [Permission.camera.request] (ERROR_ALREADY_REQUESTING_PERMISSIONS).
  static Future<bool>? _cameraPermissionOngoing;

  /// Gets the current camera permission status without requesting.
  static Future<PermissionStatus> getCameraPermissionStatus() async {
    return Permission.camera.status;
  }

  /// Read-only: whether the camera is currently allowed (no dialog).
  static Future<bool> isCameraPermissionGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Read-only: whether the user must open Settings to grant camera access.
  static Future<bool> isCameraPermissionPermanentlyDenied() async {
    final status = await getCameraPermissionStatus();
    return status == PermissionStatus.permanentlyDenied;
  }

  /// Ensures camera permission, requesting the system dialog if needed.
  /// All concurrent calls await the same in-flight request.
  static Future<bool> ensureCameraPermission() async {
    final status = await Permission.camera.status;
    dev.log("📷 Camera permission initial status: $status");

    if (status.isGranted) {
      dev.log("📷 Camera permission already granted");
      return true;
    }

    if (_cameraPermissionOngoing != null) {
      return _cameraPermissionOngoing!;
    }
    _cameraPermissionOngoing = _requestCamera().whenComplete(() {
      _cameraPermissionOngoing = null;
    });
    return _cameraPermissionOngoing!;
  }

  static Future<bool> _requestCamera() async {
    dev.log("📷 Requesting camera permission...");
    try {
      final result = await Permission.camera.request();
      dev.log("📷 Camera permission request result: $result");
      if (result.isPermanentlyDenied) {
        dev.log(
          "📷 Camera permission permanently denied - need to open settings",
        );
      }
      return result.isGranted;
    } on PlatformException catch (e) {
      if (e.code == "ERROR_ALREADY_REQUESTING_PERMISSIONS") {
        dev.log("📷 Camera: already requesting; re-checking status: $e");
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final s = await Permission.camera.status;
        return s.isGranted;
      }
      rethrow;
    }
  }

  /// Opens app settings so user can manually enable permissions
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
