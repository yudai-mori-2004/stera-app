import "dart:developer";

import "package:stera/src/core/enums/platform_channel_methods.dart";
import "package:stera/src/core/enums/platform_channels.dart";

class VideoPickerMethodChannels {
  static const _channel = PlatformChannels.videoPicker;

  static Future<List<String>?> pickVideos() async {
    try {
      final result = await _channel.channel.invokeMethod<List<dynamic>>(
        VideoPickerMethod.pickVideos.methodName,
      );
      if (result == null) return null;
      return result.cast<String>();
    } catch (e) {
      log("Error picking videos: $e");
      return null;
    }
  }

  static Future<String?> pickSingleVideo() async {
    try {
      final result = await _channel.channel.invokeMethod<String>(
        VideoPickerMethod.pickSingleVideo.methodName,
      );
      return result;
    } catch (e) {
      log("Error picking single video: $e");
      return null;
    }
  }
}
