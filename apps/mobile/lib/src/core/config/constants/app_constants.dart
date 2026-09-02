import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/config/constants/brand.dart";

class AppConstants {
  static String get scheme =>
      AppConfig.host.contains("localhost") || AppConfig.host.contains("192.168")
      ? "http"
      : "https";
  static const String termsAndConditions = Brand.termsAndConditions;
  static const String privacyPolicy = Brand.privacyPolicy;
  static const String contactEmail = Brand.contactEmail;
  static const String discordInvite = Brand.discordInvite ?? "";
  static const String sourceRepo = Brand.sourceRepo;
}
