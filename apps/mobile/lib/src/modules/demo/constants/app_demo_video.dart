import "package:flutter_dotenv/flutter_dotenv.dart";

/// Hosted product demo (landscape) — in-app recording and spatial viewer.
///
/// Read from `DEMO_VIDEO_URL` in `.env` so forks point at their own hosting
/// instead of inheriting ours. Unset is a supported state: [isConfigured] is
/// false and the intro card shows the still thumbnail instead of playback.
abstract final class AppDemoVideo {
  AppDemoVideo._();

  static String get url {
    if (!dotenv.isInitialized) return "";
    return dotenv.env["DEMO_VIDEO_URL"] ?? "";
  }

  static bool get isConfigured => url.isNotEmpty;
}
