import "dart:developer";
import "package:stera/src/core/config/constants/app_constants.dart";
import "package:flutter/widgets.dart";
import "package:url_launcher/url_launcher_string.dart";

class AppUrlLauncher {
  static Future<void> launchUrl(String url, {bool sanitizeUrl = false}) async {
    try {
      if (sanitizeUrl) {
        if (!url.startsWith("https") || !url.startsWith("http")) {
          url = "https://$url";
        }
      }
      await launchUrlString(url, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      log("Error launching url: $url", error: e);
    }
  }

  static Future<void> launchEmail({
    required BuildContext context,
    String subject = "Get Enterprise Plan",
    String? body,
  }) async {
    final query = StringBuffer("subject=${Uri.encodeComponent(subject)}");
    if (body != null && body.isNotEmpty) {
      query.write("&body=${Uri.encodeComponent(body)}");
    }
    final url = Uri.parse(
      "mailto:${AppConstants.contactEmail}?$query",
    );

    try {
      await launchUrlString(url.toString());
    } catch (e) {
      log("Error launching email: ${AppConstants.contactEmail}", error: e);
    }
  }
}
