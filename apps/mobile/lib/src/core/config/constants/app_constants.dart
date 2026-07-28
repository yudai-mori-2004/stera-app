import "package:stera/src/core/config/app_config.dart";

class AppConstants {
  static String get scheme =>
      AppConfig.host.contains("localhost") || AppConfig.host.contains("192.168")
      ? "http"
      : "https";
  static const String termsAndConditions = "https://www.fpvlabs.ai/terms";
  static const String privacyPolicy = "https://www.fpvlabs.ai/privacy";
  static const String contactEmail = "contact@fpvlabs.ai";
  static const String discordInvite = "https://www.fpvlabs.ai/discord";
  static const String sourceRepo = "https://github.com/fpv-labs/stera-app";
}
