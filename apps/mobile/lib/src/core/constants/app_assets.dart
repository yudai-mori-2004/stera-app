import "package:flutter/material.dart";

class AppAssets {
  static const String texture = "assets/images/ui/scaffold_texture.png";
  static const String logo = "assets/icon/logo_light.png";
  static const String logoDark = "assets/icon/logo_dark.png";

  /// Light-theme logo PNG ([logo]) vs dark-theme ([logoDark]).
  static String logoForBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? logoDark : logo;

  /// Resolved logo path for [context]'s current [ThemeData.brightness].
  static String logoAsset(BuildContext context) =>
      logoForBrightness(Theme.of(context).brightness);
  static const String lines = "assets/images/ui/vector_perspective.svg";

  // Onboarding images
  static const String onboarding1 = "assets/images/onboarding/image1.png";
        static const String wave = "assets/images/ui/wave.svg";
  static const String logoutIcon = "assets/icon/logout.svg";
  static const String googleIcon = "assets/icon/google.svg";

  // Home stats icons
      static const String arrowSquareUpIcon = "assets/icon/arrow-square-up.svg";
  static const String surprisedStatue = "assets/images/surprised_statue.png";

  // Bottom nav bar icons
    static const String navHomeIcon = "assets/icon/nav_bar/home.svg";
  static const String navPlusIcon = "assets/icon/nav_bar/plus.svg";
  
  
  /// Home card preview for the product demo video (spatial viewer screenshot).
  static const String appVidDemoThumbnail =
      "assets/images/app_vid_demo_thumbnail.png";

      static String update(Brightness brightness) => brightness == Brightness.dark
      ? "assets/images/update_dark.png"
      : "assets/images/update.png";
  static const String announcement = "assets/icon/announcements.svg";
}
