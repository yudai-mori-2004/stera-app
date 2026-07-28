import "package:stera/src/core/config/constants/app_endpoints.dart";
import "package:stera/src/modules/home/data/models/video_metadata.dart";
import "package:stera/src/services/api/api.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/enums/method_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";

class UploadedVideosRepo {
  static Future<(List<VideoMetadata>?, Failure?)> getUploadedVideos() async {
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.assets,
        method: MethodType.get,
      );

      if (err != null) {
        return (null, err);
      }

      final videos =
          ((res as Map<String, dynamic>)["data"] as List<dynamic>? ?? [])
              .map(
                (item) => VideoMetadata.fromMap(item as Map<String, dynamic>),
              )
              .toList();

      return (videos, null);
    } catch (e) {
      return (null, Failure(message: e.toString(), code: ErrorType.unknown));
    }
  }
}
