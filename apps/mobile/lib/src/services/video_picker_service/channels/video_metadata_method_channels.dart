import "dart:developer";
import "package:stera/src/core/enums/platform_channel_methods.dart";
import "package:stera/src/core/enums/platform_channels.dart";

class VideoMetadataMethodChannels {
  static const _channel = PlatformChannels.videoHelper;

  static Future<String?> extractThumbnail(Uri uri, {int timeMs = 0}) async {
    try {
      final result = await _channel.channel.invokeMethod<String>(
        VideoHelperMethod.extractThumbnail.methodName,
        {"uri": uri.toString(), "timeMs": timeMs},
      );
      return result;
    } catch (e) {
      log("Error extracting thumbnail: $e");
      return null;
    }
  }

  static Future<int?> getVideoDuration(Uri uri) async {
    try {
      final result = await _channel.channel.invokeMethod<int>(
        VideoHelperMethod.getVideoDuration.methodName,
        {"uri": uri.toString()},
      );
      return result;
    } catch (e) {
      log("Error getting video duration: $e");
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getVideoMetadata(Uri uri) async {
    try {
      final result = await _channel.channel.invokeMethod<Map<dynamic, dynamic>>(
        VideoHelperMethod.getVideoMetadata.methodName,
        {"uri": uri.toString()},
      );
      return result?.map((key, value) => MapEntry(key.toString(), value));
    } catch (e) {
      log("Error getting video metadata: $e");
      return null;
    }
  }

  static Future<bool> openVideoInViewer(Uri uri) async {
    try {
      final result = await _channel.channel.invokeMethod<bool>(
        VideoHelperMethod.openVideoInViewer.methodName,
        {"uri": uri.toString()},
      );
      return result ?? false;
    } catch (e) {
      log("Error opening video in viewer: $e");
      return false;
    }
  }

  static Future<bool> saveVideoToGallery(String sourcePath) async {
    try {
      final result = await _channel.channel.invokeMethod<bool>(
        VideoHelperMethod.saveVideoToGallery.methodName,
        {"sourcePath": sourcePath},
      );
      return result ?? false;
    } catch (e) {
      log("Error saving video to gallery: $e");
      return false;
    }
  }
}
